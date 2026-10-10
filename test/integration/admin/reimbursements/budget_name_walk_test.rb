require "test_helper"
require "csv"
require "rubyXL" # BacsXlsx requires it lazily; the walk reads the workbook and the BACS sheet
require_relative "../../../support/expense_import_sheet_helpers"

module Admin
  module Reimbursements
    ##
    # The mechanical check of "a budget shown on its own names its area"
    # (Budget#display_name). Grep sweeps for bare names kept missing sites, so
    # this seeds lines that share a name across areas and cost centres, gives
    # every screen rows, then reads every portal page, export and email that can
    # name a budget. Any text naming one of those lines bare fails, unless it
    # sits in one of the ALLOWED_CONTEXTS.
    #
    # A new screen or output that names budgets belongs in one of these walks.
    class BudgetNameWalkTest < ActionDispatch::IntegrationTest
      include ReimbursementsTestHelpers
      include ExpenseImportSheetHelpers
      include Devise::Test::IntegrationHelpers

      # Each repeated line name, and the areas holding a line of that name.
      # Freshers is in the second cost centre. No loose line shares a name: its
      # display name is bare, so text alone could not tell it from a mistake.
      SHARED_NAMES = {
        "Marketing" => %w[Cogito Improverts Freshers],
        "Sponsorship" => %w[Cogito Improverts]
      }.freeze

      # Where a line's bare name is right, because its area is beside it.
      # Anywhere else, a SHARED_NAMES line must be named with its area.
      ALLOWED_CONTEXTS = {
        area_rowgroup: "a row under its area's rowgroup heading (the grouped budgets index, " \
                       "the overview's area card)",
        own_page: "the body of a line's or an area's own page, whose heading names the area",
        name_field: "a budget form's name field, which edits the stored name",
        area_column: "a cell read with its row's Area cell (an export's Budget column, " \
                     "the budget import preview's sheet rows)"
      }.freeze

      # Shown or announced to a reader, as well as text nodes. These are read
      # away from the table and heading around them (a screen reader's links
      # list does not announce the rowgroup heading), so no context excuses one.
      READ_ATTRIBUTES = %w[aria-label aria-description title alt placeholder label
                           data-turbo-confirm].freeze

      # A line's or an area's own page (no /edit).
      OWN_PAGE_PATH = %r{\A/admin/reimbursements/(?:areas|budgets)/\d+\z}

      setup do
        @finance = users(:admin)
        @producer = users(:member)
        @owner_user = users(:member_with_phone_number)
        grant_producer_permission(@producer)
        grant_producer_permission(@owner_user)
        @allowed_hits = Hash.new(0)
        seed_world
      end

      # --- The seeded world ------------------------------------------------------

      def seed_world
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        @fringe = ::Reimbursements::CostCentre.default
        @termtime = create_second_reimbursements_cost_centre(
          sharepoint_receipts_drive_id: "drvR", sharepoint_receipts_folder_id: "fldR",
          sharepoint_bacs_drive_id: "drvB", sharepoint_bacs_folder_id: "fldB"
        )
        @payee = create_reimbursements_person(name: "Pat Producer", email: @producer.email,
                                              sort_code: "08-99-99", account_number: "66374958",
                                              verified: true)
        @owner = create_reimbursements_person(name: "Olive Owner", email: @owner_user.email)
        seed_lines
        seed_claims
        seed_ledger
        seed_forecasts
      end

      def seed_lines
        @areas = {
          "Cogito" => create_reimbursements_area(name: "Cogito", cost_centre: @fringe),
          "Improverts" => create_reimbursements_area(name: "Improverts", cost_centre: @fringe),
          "Freshers" => create_reimbursements_area(name: "Freshers", cost_centre: @termtime)
        }
        # Cogito's claims wait for its owner; the other areas name nobody, so theirs skip the gate.
        @areas["Cogito"].owners << @owner

        @lines = {}
        SHARED_NAMES.each do |name, area_names|
          income = name == "Sponsorship"
          area_names.each do |area_name|
            area = @areas.fetch(area_name)
            @lines["#{area_name}: #{name}"] = create_reimbursements_budget(
              name: name, nominal_code: income ? "410000" : "432320", area: area,
              cost_centre: area.cost_centre, budget_type: income ? "Income" : "Expense",
              # Freshers' line is overspent, so the dashboard's Budget health lists it.
              initial_budget: BigDecimal(area_name == "Freshers" ? "10" : "400")
            )
          end
        end
        @contingency = create_reimbursements_budget(name: "Contingency", nominal_code: "439999",
                                                    cost_centre: @fringe)
      end

      def line(label) = @lines.fetch(label)

      # A claim in every status, so every list and tab has rows.
      def seed_claims
        @batch = create_reimbursements_batch(name: "Batch 2026-05-13")
        status = ::Reimbursements::Status
        @claims = {
          gated: claim(1, "Cogito: Marketing", status::PENDING),
          pending: claim(2, "Improverts: Marketing", status::PENDING),
          approved: claim(3, "Freshers: Marketing", status::APPROVED),
          approved_fringe: claim(4, "Improverts: Marketing", status::APPROVED),
          submitted: claim(5, "Cogito: Marketing", status::SUBMITTED, batch: @batch),
          paid: claim(6, "Improverts: Marketing", status::PAID, batch: @batch),
          draft: claim(7, "Cogito: Marketing", status::DRAFT),
          rejected: claim(8, "Freshers: Marketing", status::REJECTED, rejection_reason: "Duplicate")
        }
      end

      def claim(number, label, status, **attrs)
        create_reimbursements_expense(person: @payee, budget: line(label), status: status,
                                      auto_number: number, submitted_at: 5.days.ago, **attrs)
      end

      # A debit on a claim, one on nothing, a credit booked to a line, one split
      # across two lines and one on nothing.
      def seed_ledger
        create_reimbursements_eusa_actual(nominal_code: "432320", narrative: "Pat Producer",
                                          debit: BigDecimal("12.50"), expense: @claims[:paid],
                                          cost_centre: @fringe)
        @loose_debit = create_reimbursements_eusa_actual(nominal_code: "432320", narrative: "Flyer print",
                                                         debit: BigDecimal("12.50"), cost_centre: @fringe)
        create_reimbursements_eusa_actual(nominal_code: "410000", narrative: "Sponsor A",
                                          credit: BigDecimal("300"), budget: line("Cogito: Sponsorship"),
                                          cost_centre: @fringe)
        split = create_reimbursements_eusa_actual(
          nominal_code: "410000", narrative: "Stripe payout", credit: BigDecimal("500"), cost_centre: @fringe,
          reconciliation_status: ::Reimbursements::EusaActual::STATUS_APPORTIONED
        )
        split.allocations.create!(budget: line("Cogito: Sponsorship"), amount: BigDecimal("200"))
        split.allocations.create!(budget: line("Improverts: Sponsorship"), amount: BigDecimal("300"))
        @loose_credit = create_reimbursements_eusa_actual(nominal_code: "410000", narrative: "Sponsor B",
                                                          credit: BigDecimal("150"), cost_centre: @fringe)
      end

      def seed_forecasts
        @budget_update = ::Reimbursements::BudgetUpdate.create!(effective_date: Date.current,
                                                                note: "Committee meeting",
                                                                created_by: @finance)
        %w[Cogito Improverts].each do |area_name|
          @budget_update.forecasts.create!(budget: line("#{area_name}: Marketing"),
                                           amount: BigDecimal("450"), date: Date.current,
                                           reason: "More flyers")
        end
        @budget_update.forecasts.create!(area: @areas["Cogito"], amount: BigDecimal("2000"),
                                         date: Date.current, reason: "Agreed total")
      end

      # --- Finding bare names ----------------------------------------------------

      # The SHARED_NAMES that +text+ names without their area. "Cogito: Marketing"
      # is qualified, and so is "Cogito Marketing", the colon-free form receipt
      # filenames and BACS references carry.
      def bare_names_in(text)
        SHARED_NAMES.filter_map do |name, area_names|
          rest = text.to_s.gsub(/\b(?:#{area_names.join('|')}):?\s+#{name}\b/i, "")
          name if rest.match?(/\b#{name}\b/i)
        end
      end

      # Whether +text+ names an area holding a line of each of +names+.
      def names_area_of?(text, names)
        names.all? { |name| SHARED_NAMES.fetch(name).any? { |area_name| text.to_s.include?(area_name) } }
      end

      # Every bare-name site in an HTML page or email, as "<where>: <text> at <element>",
      # leaving out the ALLOWED_CONTEXTS. The sidebar is navigation (its
      # "Marketing Creatives" link is not a budget); flash messages are read from
      # the flash, not the script that shows them.
      def html_sites(html, where, path: nil)
        doc = Nokogiri::HTML4(html)
        doc.css("aside.sidebar, script, style").each(&:remove)
        page = { path: path, heading: doc.at_css("header h1")&.text }
        sites = []
        doc.traverse do |node|
          readable_strings(node).each do |text, kind|
            names = bare_names_in(text)
            next if names.empty? || allowed_in_page?(node, kind, names, page)

            sites << "#{where}: #{text.squish.truncate(160).inspect} at #{css_trail(node)}"
          end
        end
        sites
      end

      # What a reader sees or hears of +node+, each with its kind: :text, a
      # READ_ATTRIBUTES :label, or a visible control's :value.
      def readable_strings(node)
        return [ [ node.text, :text ] ] if node.text?
        return [] unless node.element?

        strings = READ_ATTRIBUTES.filter_map { |attribute| [ node[attribute], :label ] if node[attribute] }
        strings << [ node["value"], :value ] if node.name == "input" && node["type"] != "hidden"
        strings
      end

      def css_trail(node)
        element = node.text? ? node.parent : node
        element.css_path.split(" > ").last(4).join(" > ")
      end

      def allowed_in_page?(node, kind, names, page)
        context = allowed_context(node.text? ? node.parent : node, kind, names, page)
        @allowed_hits[context] += 1 if context
        context.present?
      end

      # The ALLOWED_CONTEXTS key that +element+ sits in, or nil.
      def allowed_context(element, kind, names, page)
        return (:name_field if budget_name_field?(element["name"])) if kind == :value
        return nil unless kind == :text
        return :area_rowgroup if under_area_rowgroup?(element, names)
        return :area_column if beside_area_cell?(element, names)

        :own_page if own_page_body?(element, names, page)
      end

      # Inside <main> of a line's or area's own page: the tab title and the
      # breadcrumb are read without the heading.
      def own_page_body?(element, names, page)
        page[:path].to_s.match?(OWN_PAGE_PATH) && element.ancestors("main").any? &&
          names_area_of?(page[:heading], names)
      end

      def budget_name_field?(field)
        field == "name" || field.to_s.match?(/\[budgets_attributes\]\[\d+\]\[name\]\z/)
      end

      # A row in a <tbody> whose rowgroup heading names the line's area.
      def under_area_rowgroup?(element, names)
        heading = element.ancestors("tbody").first&.at_css("th[scope=rowgroup]")
        return false if heading.nil? || element == heading || element.ancestors.include?(heading)

        names_area_of?(heading.text, names)
      end

      # A cell of a table whose head has an Area column, in a row whose Area
      # cell names the line's area.
      def beside_area_cell?(element, names)
        cell = element.name == "td" ? element : element.ancestors("td").first
        table = cell&.ancestors("table")&.first
        return false if table.nil?

        column = table.css("thead th").map { |heading| heading.text.squish }.index("Area")
        column.present? && names_area_of?(cell.parent.css("> td")[column]&.text, names)
      end

      # Every bare-name site in an export's rows. A bare Budget cell is allowed
      # when the same row's Area cell names the line's area.
      def table_sites(rows, where)
        headers, *body = rows
        area_column = headers.index("Area")
        body.each_with_index.flat_map do |cells, index|
          cells.each_with_index.filter_map do |cell, column|
            names = bare_names_in(cell)
            next if names.empty?
            if headers[column] == "Budget" && area_column && names_area_of?(cells[area_column], names)
              @allowed_hits[:area_column] += 1
              next
            end

            "#{where} row #{index + 2}, #{headers[column].inspect}: #{cell.inspect}"
          end
        end
      end

      # Fails on any site, and on any of +used+ the walk never met: an allowance
      # nothing exercises means the walk stopped reading the screen it covers.
      def assert_no_bare_names(sites, used: [])
        assert_empty sites, "A budget named without its area:\n#{sites.join("\n")}\n" \
                            "Name it with Budget#display_name (#picker_label in a <select>), or add " \
                            "the context to ALLOWED_CONTEXTS with its reason."
        used.each do |context|
          assert @allowed_hits[context].positive?, "the walk never met #{ALLOWED_CONTEXTS.fetch(context)}"
        end
      end

      # Signs in as +user+ and reads each path, failing on any page that does not render.
      def walk(user, paths)
        sign_in user
        paths.flat_map do |path|
          get path
          assert_response :success, "#{path} as #{user.email}: #{response.status} #{response.location}"
          html_sites(response.body, path, path: path)
        end
      end

      # The flash a request left, read as page text.
      def flash_sites(where)
        flash.to_h.values.flat_map { |message| bare_names_in(message).map { "#{where} flash: #{message.inspect}" } }
      end

      def area_id(name) = @areas.fetch(name).record_id

      def line_ids = @lines.values.map(&:record_id) + [ @contingency.record_id ]

      # --- The walks ---------------------------------------------------------------

      test "finance's screens name the area of every line they name" do
        paths = [
          admin_reimbursements_root_path,
          admin_reimbursements_budgets_path,
          admin_reimbursements_budgets_path(cost_centre: "termtime"),
          overview_admin_reimbursements_budgets_path,
          overview_admin_reimbursements_budgets_path(cost_centre: "fringe"),
          new_admin_reimbursements_budget_path,
          *line_ids.flat_map { |id| [ edit_admin_reimbursements_budget_path(id), admin_reimbursements_budget_path(id) ] },
          admin_reimbursements_areas_path,
          new_admin_reimbursements_area_path,
          *@areas.keys.flat_map do |name|
            [ admin_reimbursements_area_path(area_id(name)), edit_admin_reimbursements_area_path(area_id(name)) ]
          end,
          *ReviewController::TABS.map { |tab| admin_reimbursements_review_path(tab: tab) },
          admin_reimbursements_expense_edits_path,
          *@claims.values.map { |expense| edit_admin_reimbursements_expense_edit_path(expense.record_id) },
          admin_reimbursements_actuals_path,
          admin_reimbursements_actuals_path(state: "all"),
          link_expense_admin_reimbursements_actual_path(@loose_debit.record_id),
          new_expense_admin_reimbursements_actual_path(@loose_debit.record_id),
          offset_pair_admin_reimbursements_actual_path(@loose_debit.record_id),
          apportion_admin_reimbursements_actual_path(@loose_credit.record_id),
          admin_reimbursements_reconciliation_path,
          new_admin_reimbursements_batch_path(cost_centre: "fringe"),
          new_admin_reimbursements_batch_path(cost_centre: "termtime"),
          admin_reimbursements_batches_path,
          admin_reimbursements_batch_path(@batch.record_id),
          admin_reimbursements_budget_updates_path,
          admin_reimbursements_budget_update_path(@budget_update.record_id),
          new_admin_reimbursements_budget_update_path,
          admin_reimbursements_people_path,
          admin_reimbursements_export_path
        ]
        sites = walk(@finance, paths)

        # Reconcile's preview, with a credit it matches to an income line, and an
        # offsetting pair whose credit leg would be logged against one if unticked.
        post preview_admin_reimbursements_reconciliation_path, params: {
          pasted_text: [ ACTUALS_HEADER,
                         "410000\tF40\tBACS002\t13/05/2026\t03\tSponsor C\tGift\t\t250.00\t-250.00",
                         "410000\tF40\tREV7\t14/05/2026\t03\tSponsor D\tAccrual\t75.00\t\t75.00",
                         "410000\tF40\tREV7\t14/05/2026\t03\tSponsor D\tReversal\t\t75.00\t-75.00" ].join("\n")
        }
        assert_response :success
        assert_select "td[colspan=7]", text: /logged against the/, count: 1
        sites += html_sites(response.body, "reconcile preview")

        # A budget update refused for an unreadable amount names the line in its alert.
        post admin_reimbursements_budget_updates_path, params: {
          effective_date: Date.current.iso8601, amounts: { line("Cogito: Marketing").record_id => "lots" }
        }
        assert_response :unprocessable_entity
        sites += html_sites(response.body, "refused budget update") + flash_sites("refused budget update")

        assert_no_bare_names(sites, used: %i[area_rowgroup own_page name_field])
      end

      test "a producer's screens name the area of every line they name" do
        paths = [
          admin_reimbursements_expenses_path,
          new_admin_reimbursements_expense_path,
          *@claims.values.map { |expense| admin_reimbursements_expense_path(expense.record_id) },
          edit_admin_reimbursements_expense_path(@claims[:draft].record_id),
          admin_reimbursements_my_budgets_path
        ]

        assert_no_bare_names(walk(@producer, paths))
      end

      test "a budget owner's screens name the area of every line they name" do
        paths = [
          admin_reimbursements_my_budgets_path,
          admin_reimbursements_area_path(area_id("Cogito")),
          admin_reimbursements_budget_path(line("Cogito: Marketing").record_id)
        ]

        assert_no_bare_names(walk(@owner_user, paths), used: %i[own_page])
      end

      # Both previews state the line each row lands on, and the budget import
      # lists the lines a sheet leaves out.
      test "the import previews name the area of every line they name" do
        sign_in @finance

        post preview_admin_reimbursements_budget_import_path, params: {
          year: @year.key, cost_centre_id: @fringe.id,
          pasted_text: [ ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t"),
                         "Cogito\t2000\tMarketing\t432320\tExpense\t500\t\t" ].join("\n")
        }
        assert_response :success
        assert_select "p", text: /aren't in this sheet/, count: 1 # the absent lines are listed
        sites = html_sites(response.body, "budget import preview")

        post preview_admin_reimbursements_expense_import_path, params: {
          year: @year.key, cost_centre_id: @fringe.id,
          pasted_text: expense_import_sheet(
            expense_import_row(payee_email: @producer.email, budget: "Improverts: Marketing")
          )
        }
        assert_response :success
        assert_select "td.font-mono", text: "OLD-1", count: 1 # the row is a create, naming its line
        sites += html_sites(response.body, "expense import preview")

        assert_no_bare_names(sites, used: %i[area_column])
      end

      test "every export names the area of every line it names" do
        sign_in @finance
        csvs = [
          admin_reimbursements_budgets_path(format: :csv),
          *ReviewController::TABS.map { |tab| admin_reimbursements_review_path(tab: tab, format: :csv) },
          admin_reimbursements_expense_edits_path(format: :csv),
          admin_reimbursements_actuals_path(state: "all", format: :csv),
          admin_reimbursements_batches_path(format: :csv)
        ]
        sites = csvs.flat_map do |path|
          get path
          assert_response :success, path
          table_sites(CSV.parse(response.body), path)
        end

        get download_admin_reimbursements_export_path
        assert_response :success
        RubyXL::Parser.parse_buffer(response.body).worksheets.each do |sheet|
          rows = sheet.sheet_data.rows.map { |row| row ? row.cells.map { |cell| cell&.value.to_s } : [] }
          sites += table_sites(rows, "workbook sheet #{sheet.sheet_name.inspect}")
        end

        assert_no_bare_names(sites, used: %i[area_column])
      end

      test "every email and batch file naming a budget names its area" do
        graph = FakeGraphClient.new
        checker = FakeModulusChecker.new("66374958" => ::Reimbursements::ModulusCheck::VALID)
        with_seams(
          [ ::Reimbursements::NightlyBatchJob, :graph_builder ] => -> { graph },
          [ ::Reimbursements::NightlyBatchJob, :checker_builder ] => -> { checker },
          [ ::Reimbursements::BuildBatchJob, :graph_builder ] => -> { graph },
          # On ReviewController, as its own suites write it: a write there shadows BaseController's.
          [ ReviewController, :notifier_builder ] =>
            ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: graph) }
        ) { assert_no_bare_names(mail_and_batch_sites(graph)) }
      end

      # Sets class_attribute seams for the block, then puts back what was there.
      def with_seams(seams)
        previous = seams.keys.to_h { |owner, seam| [ [ owner, seam ], owner.public_send(seam) ] }
        seams.each { |(owner, seam), value| owner.public_send("#{seam}=", value) }
        yield
      ensure
        previous&.each { |(owner, seam), value| owner.public_send("#{seam}=", value) }
      end

      # Sends every email that names a budget and builds a batch, then reads them.
      def mail_and_batch_sites(graph)
        # The owner sign-off reminder and both centres' approved queues.
        ::Reimbursements::NightlyBatchJob.perform_now(today: Date.new(2026, 7, 9))

        sign_in @finance
        # A rejection, emailed to the producer.
        patch admin_reimbursements_reject_review_path(@claims[:pending].record_id),
              params: { rejection_reason: "Wrong show", tab: "to_approve" }
        assert_response :redirect
        sites = flash_sites("rejection")

        # An approval with no payment reference, which Review derives from the
        # line's name; the batch's BACS sheet carries it.
        unreferenced = claim(9, "Freshers: Marketing", ::Reimbursements::Status::PENDING, payment_reference: "")
        patch admin_reimbursements_approve_review_path(unreferenced.record_id), params: { tab: "to_approve" }
        assert_response :redirect
        assert_predicate unreferenced.reload.payment_reference, :present?
        sites += bare_names_in(unreferenced.payment_reference).map { "derived reference #{unreferenced.payment_reference.inspect}" }

        # A batch: the EUSA covering email and BACS sheet, the receipt filenames,
        # the producer's notification and the operator's draft-ready email.
        attempt = ::Reimbursements::BatchAttempt.create!(cost_centre: @termtime, bacs_date: Date.new(2026, 7, 10))
        ::Reimbursements::BuildBatchJob.perform_now(
          cost_centre_key: @termtime.key, bacs_date: "2026-07-10", sender_name: "Finance",
          eusa_recipient: "finance@eusa.example", operator_emails: [ "ops@example.com" ],
          attempt_id: attempt.id
        )
        assert_equal "completed", attempt.reload.status, attempt.error_messages

        assert_equal %w[approved_ready batch_ready owner_sign_off_reminder producer_notification rejection],
                     ::Reimbursements::NotificationLog.distinct.pluck(:kind).sort - %w[pending_reminder],
                     "every email that names a budget was sent"
        graph.send_mails.each { |mail| sites += mail_sites(mail, "email") }
        graph.drafts.each do |draft|
          sites += mail_sites(draft, "EUSA draft")
          sites += draft[:attachments].flat_map { |name| bare_names_in(name).map { "draft attachment #{name.inspect}" } }
        end
        assert graph.uploaded.any? { |upload| upload[:filename].end_with?(".xlsx") }, "the BACS sheet was uploaded"
        graph.uploaded.each { |upload| sites += upload_sites(upload) }
        sites
      end

      # A sent email's or draft's subject and body.
      def mail_sites(mail, kind)
        where = "#{kind} #{mail[:subject].inspect}"
        bare_names_in(mail[:subject]).map { "#{where} subject" } + html_sites(mail[:html], where)
      end

      # A receipt's filename, and every cell of an uploaded spreadsheet.
      def upload_sites(upload)
        sites = bare_names_in(upload[:filename]).map { "uploaded file #{upload[:filename].inspect}" }
        return sites unless upload[:filename].end_with?(".xlsx")

        RubyXL::Parser.parse_buffer(upload[:content]).worksheets.each do |sheet|
          sheet.sheet_data.rows.compact.flat_map(&:cells).compact.each do |cell|
            value = cell.value.to_s
            sites << "#{upload[:filename]} #{sheet.sheet_name}: #{value.inspect}" if bare_names_in(value).any?
          end
        end
        sites
      end
    end
  end
end
