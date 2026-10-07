require "test_helper"

module Admin
  module Reimbursements
  class ReconcileControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze

    # DatabaseStore whose actual-link writes raise for chosen targets.
    class FlakyLinkStore < ::Reimbursements::DatabaseStore
      attr_accessor :fail_expense_link_ids, :fail_budget_links

      def initialize(fail_expense_link_ids: [], fail_budget_links: false)
        super()
        @fail_expense_link_ids = fail_expense_link_ids
        @fail_budget_links = fail_budget_links
      end

      def link_actual_to_expense!(actual_id, expense_id)
        raise "blip" if fail_expense_link_ids.include?(expense_id.to_s)

        super
      end

      def link_actual_to_budget!(actual_id, budget_id)
        raise "blip" if fail_budget_links

        super
      end
    end

    # DatabaseStore that fails part-way through writing an offsetting pair: on the second leg's insert or the cross-link.
    class HalfPairStore < ::Reimbursements::DatabaseStore
      def initialize(fail_on:)
        super()
        @fail_on = fail_on
        @creates = 0
      end

      def create_actual!(attrs)
        @creates += 1
        raise "blip" if @fail_on == :second_leg && @creates == 2

        super
      end

      def link_offsetting_pair!(actual_id, counterpart_id)
        raise "blip" if @fail_on == :link

        super
      end
    end

    setup do
      @user = users(:member)
      grant_finance_permission(@user)

      # A Submitted expense the debit row matches: nominal 439999, 123.45 excl VAT, submitted within 14 days.
      @person = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
      @budget = create_reimbursements_budget(name: "Props", nominal_code: "439999")
      @income = create_reimbursements_budget(name: "Ticket income", nominal_code: "250000",
                                             budget_type: "Income")
      @expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("123.45"),
        amount_excl_vat: BigDecimal("123.45"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), receipt: false
      )

      # Reconcile emails nobody: a real Notifier over a recording FakeGraphClient makes the no-email
      # test a genuine assertion, and a regression records here instead of reaching Graph.
      @graph = FakeGraphClient.new
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
    end

    teardown do
      BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
    end

    def debit_row(nominal: "439999", date: "13/05/2026", period: "03", narrative: "Alice Producer",
                  debit: "123.45", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS001\t#{date}\t#{period}\t#{narrative}\tShow\t#{debit}\t\t#{debit}"
    end

    def credit_row(nominal: "250000", period: "03", narrative: "Box office", credit: "500.00",
                   cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS002\t13/05/2026\t#{period}\t#{narrative}\tTickets\t\t#{credit}\t-#{credit}"
    end

    def fringe_cost_centre
      ::Reimbursements::CostCentre.find_by!(eusa_code: "F40")
    end

    # --- Step 1: show ------------------------------------------------------

    test "show renders the paste form" do
      sign_in @user
      get :show

      assert_response :success
      assert_includes response.body, "Paste actuals data"
      assert_match(/emails its ledger export once a month/, response.body)
      assert_match(/ask them for the latest one/, response.body)
    end

    # --- Step 2: preview / parse + dedup + match ---------------------------

    # Saying so beats guessing a code, which would file another centre's ledger under this one.
    test "preview says so when no cost centre is configured, rather than assuming one" do
      sign_in @user
      ::Reimbursements::CostCentre.delete_all

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_includes response.body, "No cost centre is set up yet"
      assert_nil assigns(:matched_debits)
    end

    test "preview matches a debit row to a submitted expense" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      row, expense = assigns(:matched_debits).first
      assert_equal @expense.record_id, expense.record_id
      assert_equal BigDecimal("123.45"), row.debit
      assert_empty assigns(:unmatched_rows)
      # The operator is told what Apply does, and it does not include emailing.
      assert_match(/Nobody is emailed/, response.body)
      assert_no_match(/email those producers/, response.body)
      assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@expense.record_id)
      assert_includes response.body, "Step 2"
      assert_includes response.body, "Step 3"
    end

    test "preview shows the gross amount of a claim matched on gross because its ex-VAT amount is 0" do
      @expense.update!(amount_excl_vat: BigDecimal("0"))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
      assert_select "tbody tr td:last-child", text: "£123.45"
      assert_select "tbody tr td:last-child", text: "£0.00", count: 0
    end

    test "preview matches a credit row to an income budget" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_credits).size
      _row, budget = assigns(:matched_credits).first
      assert_equal @income.record_id, budget.record_id
    end

    test "preview re-renders show with an alert on a malformed paste (missing header columns)" do
      sign_in @user
      bad_header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      post :preview, params: { pasted_text: "#{bad_header}\n#{debit_row}" }

      assert_response :success
      assert_includes response.body, "Could not parse actuals"
    end

    test "preview alerts when the paste has only a header row, no data" do
      sign_in @user
      post :preview, params: { pasted_text: HEADER }

      assert_response :success
      assert_includes response.body, "No data rows found"
    end

    test "apply redirects with an alert on a malformed paste" do
      sign_in @user
      bad_header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      post :apply, params: { pasted_text: "#{bad_header}\n#{debit_row}" }

      assert_redirected_to admin_reimbursements_reconciliation_path
      assert_match(/Could not parse the actuals/, flash[:alert])
      assert_equal 0, ::Reimbursements::EusaActual.count
    end

    test "an expense with a payment_confirmed_date but no linked actual is excluded from matching" do
      @expense.update!(payment_confirmed_date: Date.new(2026, 5, 1))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits), "already-paid-by-another-route expenses must not be re-matched"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "a single paste dedups each period independently" do
      create_reimbursements_actual(nominal_code: "439999", period: "03",
                                   narrative: "Alice Producer", debit: BigDecimal("123.45"))
      sign_in @user

      two_rows = "#{HEADER}\n#{debit_row(period: '03')}\n#{debit_row(period: '04')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_equal "03", assigns(:skipped_rows).first.period
      assert_equal 1, assigns(:new_rows).size
      assert_equal "04", assigns(:new_rows).first.period
    end

    test "one expense is claimed by at most one debit row" do
      sign_in @user
      two_rows = "#{HEADER}\n#{debit_row}\n#{debit_row(date: '14/05/2026')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      assert_equal 1, assigns(:unmatched_rows).size, "the second row can't reclaim the same expense"
    end

    # --- Step 3: apply -----------------------------------------------------

    test "apply creates actuals, links them, and flips the expense to Paid without emailing" do
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_empty @graph.send_mails, "marking an expense Paid must not email the producer"
      assert_match(/Nobody was emailed/, response.body, "and the apply page says so")

      assert_response :success
      actual = ::Reimbursements::EusaActual.sole
      assert_equal [ @expense.record_id ], actual.linked_expense_ids
      @expense.reload
      assert_equal ::Reimbursements::Status::PAID, @expense.status
      assert_equal Date.new(2026, 5, 13), @expense.payment_confirmed_date
      assert_equal 1, assigns(:expenses_paid)
      assert_not_includes response.body, "on the EUSA Actuals ledger"
    end

    test "apply links a matched credit to its budget" do
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal [ @income.record_id ], ::Reimbursements::EusaActual.sole.linked_budget_ids
      assert_equal 1, assigns(:credits_linked)
    end

    test "apply saves an unmatched row, pays nothing, and links to the needs-attention ledger" do
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row(nominal: '999999')}"
      }

      assert_response :success
      assert_equal 1, assigns(:unmatched_saved)
      assert_equal 0, assigns(:expenses_paid)
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
      assert_includes response.body, "on the EUSA Actuals ledger"
      assert_includes response.body, admin_reimbursements_actuals_path(state: "needs_attention")
      # A link out of the wizard's Turbo Frame needs "_top", or Turbo renders "Content missing".
      assert_select "a[data-turbo-frame='_top']"
    end

    test "an already-reconciled expense is not re-matched by a later paste" do
      # @expense was paid in an earlier period and linked to an actual. A later export carries a
      # near-identical row (different narrative) that dedup does not skip; the re-pay guard must.
      @expense.update!(status: ::Reimbursements::Status::PAID)
      create_reimbursements_actual(nominal_code: "439999", period: "02",
                                   narrative: "Alice Producer OLD",
                                   debit: BigDecimal("123.45"), expense: @expense)
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row(narrative: 'Alice Producer NEW')}"
      }

      assert_response :success
      assert_equal 0, assigns(:expenses_paid)
      assert_equal 1, assigns(:unmatched_saved)
      assert_nil @expense.reload.payment_confirmed_date
    end

    test "a mid-batch row failure doesn't abort the rest, and is surfaced instead of hidden" do
      second_expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("55.00"),
        amount_excl_vat: BigDecimal("55.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), nominal_code_override: "555555",
        receipt: false
      )
      # second_expense's link write fails after its Actual was created; @expense's row is untouched.
      BaseController.store_builder = ->(**) { FlakyLinkStore.new(fail_expense_link_ids: [ second_expense.record_id ]) }
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row}\n#{debit_row(nominal: '555555', narrative: 'Alice Producer', debit: '55.00')}"
      }

      assert_response :success
      assert_equal 1, assigns(:expenses_paid)
      assert_equal ::Reimbursements::Status::PAID, @expense.reload.status
      assert_equal ::Reimbursements::Status::SUBMITTED, second_expense.reload.status
      assert_match(/expense #.*blip/i, assigns(:reconciliation_errors).sole)
      assert_match(/hit a problem/i, response.body)
    end

    test "a failed credit row is not counted in credits_linked" do
      BaseController.store_builder = ->(**) { FlakyLinkStore.new(fail_budget_links: true) }
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 0, assigns(:credits_linked), "a row whose link write failed must not count as linked"
      assert_match(/budget Ticket income.*blip/i, assigns(:reconciliation_errors).sole)
    end

    test "apply redirects when the pasted text is missing" do
      sign_in @user
      post :apply, params: { pasted_text: "" }

      assert_redirected_to admin_reimbursements_reconciliation_path
    end

    # --- Offsetting pairs --------------------------------------------------
    #
    # An accrual and its reversal on one nominal code and reference, a day apart in consecutive
    # periods: the shape that dominates a real EUSA export.

    ACCRUAL_REF = "J000000884".freeze
    ACCRUAL_NOMINAL = "331300".freeze

    def accrual_row(nominal: ACCRUAL_NOMINAL, ref: ACCRUAL_REF, date: "27/04/2026", period: "01",
                    narrative: "Venue hire accrual", amount: "500.00", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\t#{ref}\t#{date}\t#{period}\t#{narrative}\tShow\t#{amount}\t\t#{amount}"
    end

    def reversal_row(nominal: ACCRUAL_NOMINAL, ref: ACCRUAL_REF, date: "28/04/2026", period: "02",
                     narrative: "Venue hire accrual", amount: "500.00", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\t#{ref}\t#{date}\t#{period}\t#{narrative}\tShow\t\t#{amount}\t-#{amount}"
    end

    def offsetting_paste
      "#{HEADER}\n#{accrual_row}\n#{reversal_row}"
    end

    def lookalike_expense
      create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("500.00"),
        amount_excl_vat: BigDecimal("500.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 4, 27), nominal_code_override: ACCRUAL_NOMINAL,
        receipt: false
      )
    end

    test "preview proposes an offsetting pair instead of listing both legs as unmatched" do
      sign_in @user
      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      pair = assigns(:offsetting_pairs).sole
      assert_equal BigDecimal("500.00"), pair.debit_row.debit
      assert_equal BigDecimal("500.00"), pair.credit_row.credit
      assert_empty assigns(:unmatched_rows), "a paired row is not an unmatched row"
      assert_select "input[type=checkbox][name='offset_pair_keys[]'][value=?][checked=checked]", pair.key
      assert_nil assigns(:offset_pair_consequences)[pair.key][:expense]
      assert_no_match(/if you untick/i, response.body)
    end

    # The point of pairing: an accrual leg that looks like a real claim must not pay it. Only rows
    # left OUT of a pair reach the debit-to-expense matcher.
    test "apply writes a ticked pair as two cross-linked offset legs that pay nothing" do
      lookalike = lookalike_expense
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: offsetting_pair_keys(offsetting_paste) }

      legs = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal 2, legs.size, "both legs are kept for the audit trail"
      assert legs.all?(&:offset?)
      assert_equal [ legs.last.id, legs.first.id ], legs.map(&:offset_of_id)
      assert_equal [ 1, 0, 0 ], assigns.values_at("offsets_linked", "unmatched_saved", "expenses_paid")
      assert_equal ::Reimbursements::Status::SUBMITTED, lookalike.reload.status
    end

    # Unticking hands the legs back to the ordinary matcher, so a leg that matches pays: the
    # operator's judgement, not the heuristic's.
    test "an unticked pair's legs import as ordinary rows and go back to the matcher" do
      lookalike = lookalike_expense
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: [ "" ] }

      assert_equal 2, ::Reimbursements::EusaActual.count
      assert ::Reimbursements::EusaActual.none?(&:offset?)
      assert_equal [ 0, 1, 1 ], assigns.values_at("offsets_linked", "expenses_paid", "unmatched_saved")
      assert_equal ::Reimbursements::Status::PAID, lookalike.reload.status
    end

    test "a same-amount row that is not part of a pair still reaches the matcher" do
      sign_in @user
      paste = "#{offsetting_paste}\n#{debit_row}"

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_equal 1, assigns(:offsetting_pairs).size
      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
    end

    # --- The preview is honest about what unticking would do ---------------
    #
    # The matched-expenses count covers UNPAIRED rows only, but apply hands an unticked pair's legs
    # back to the matcher, so each pair states what unticking it would pay.

    test "the preview spells out the expense a pair would pay if unticked" do
      lookalike = lookalike_expense
      sign_in @user

      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      assert_empty assigns(:matched_debits), "a paired row is not in the ordinary matching"
      key = assigns(:offsetting_pairs).sole.key
      assert_equal lookalike.record_id, assigns(:offset_pair_consequences)[key][:expense].record_id
      assert_select "td[colspan=7]", text: /If you untick this pair.*##{lookalike.auto_number}/m
      assert_select "td[rowspan=3]", 2, "the checkbox and score cells span the note row"
      assert_includes response.body, "can add to that count"
    end

    # Two pairs that both look like the same expense must not both claim it:
    # apply matches each expense once, so the preview has to as well.
    test "two identical pairs never both claim the same expense if unticked" do
      lookalike_expense
      sign_in @user

      post :preview, params: { pasted_text: [ HEADER, accrual_row, reversal_row,
                                              accrual_row, reversal_row ].join("\n") }

      assert_response :success
      claimed = assigns(:offset_pair_consequences).values.filter_map { |c| c[:expense] }
      assert_equal 1, claimed.size, "the second pair has no expense left to pay"
    end

    # --- A pair is written all-or-nothing ----------------------------------
    #
    # A half-written pair leaves the debit leg unstamped, so every rollup reads it as real spend, and
    # re-pasting cannot repair it because dedup then skips that leg.

    %i[second_leg link].each do |fail_on|
      test "a pair whose #{fail_on.to_s.tr('_', ' ')} write fails writes neither leg" do
        BaseController.store_builder = ->(**) { HalfPairStore.new(fail_on: fail_on) }
        sign_in @user

        post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: offsetting_pair_keys(offsetting_paste) }

        assert_equal 0, ::Reimbursements::EusaActual.count, "a stranded leg would read as real spend forever"
        assert_equal 0, assigns(:offsets_linked)
        assert_match(/offsetting pair.*blip/i, assigns(:reconciliation_errors).sole)
      end
    end

    # --- Duplicate pairs ---------------------------------------------------
    #
    # A paste can hold the same accrual and reversal twice: two pairs, which need two tickboxes so
    # that ticking one and unticking the other means exactly that.

    def duplicate_pairs_paste
      accrual = accrual_row(amount: "10.00")
      reversal = reversal_row(amount: "10.00")
      [ HEADER, accrual, reversal, accrual, reversal ].join("\n")
    end

    test "two byte-identical pairs render as two separately tickable rows" do
      sign_in @user
      post :preview, params: { pasted_text: duplicate_pairs_paste }

      assert_response :success
      pairs = assigns(:offsetting_pairs)
      assert_equal 2, pairs.size
      assert_equal 2, pairs.map(&:key).uniq.size, "two real pairs, two keys"
      pairs.each do |pair|
        assert_select "input[type=checkbox][name='offset_pair_keys[]'][value=?][checked=checked]",
                      pair.key
        assert_select "##{"offset-pair-#{pair.key}"}", 1, "each checkbox needs its own DOM id"
      end
    end

    test "unticking one of two identical pairs offsets only the other" do
      sign_in @user
      keys = offsetting_pair_keys(duplicate_pairs_paste)
      assert_equal 2, keys.uniq.size, "the two pairs must be distinguishable to begin with"

      post :apply, params: { pasted_text: duplicate_pairs_paste, offset_pair_keys: [ keys.first ] }

      assert_response :success
      assert_equal 1, assigns(:offsets_linked)
      assert_equal 4, ::Reimbursements::EusaActual.count, "all four rows are still imported"
      assert_equal 2, ::Reimbursements::EusaActual.all.count(&:offset?),
                   "only the ticked pair's two legs are stamped offset"
      assert_equal 2, assigns(:unmatched_saved),
                   "the unticked pair's legs are imported as ordinary rows"
    end

    # --- Per-row cost centres ----------------------------------------------

    test "a paste spanning two cost centres imports every row under its own" do
      create_second_reimbursements_cost_centre
      sign_in @user
      paste = [ HEADER, debit_row(narrative: "Fringe spend"),
                debit_row(narrative: "Termtime spend", cost_centre: "BED") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      actuals = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal %w[F40 BED], actuals.map { |actual| actual.cost_centre.eusa_code },
                   "each row resolves through the association to the pot its own code named"
    end

    # Another society's spend in a whole-organisation export: skipped, but never silently.
    test "preview reports the rows it skipped for an unconfigured cost centre, and names the codes" do
      sign_in @user
      paste = [ HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12"),
                debit_row(narrative: "Someone else again", cost_centre: "H03") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_equal 2, assigns(:attribution).unrecognised_rows.size
      assert_equal %w[G12 H03], assigns(:attribution).unrecognised_codes
      assert_match(/2 rows skipped/, response.body)
      assert_match(/G12 and H03/, response.body)
    end

    test "apply imports only the rows whose cost centre is set up here" do
      sign_in @user
      paste = [ HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      assert_equal [ fringe_cost_centre.id ], ::Reimbursements::EusaActual.pluck(:cost_centre_id)
      assert_match(/not set up here/, response.body)
    end

    # --- Blank cost centres always need an explicit answer -----------------

    def blank_centre_paste
      [ HEADER, debit_row, debit_row(narrative: "No centre named", cost_centre: "") ].join("\n")
    end

    # Not inferred even here, with the fixture as the only centre: that guess files real spend under
    # the wrong pot once a second exists.
    test "preview asks where blank-cost-centre rows belong rather than assuming the only centre" do
      sign_in @user

      post :preview, params: { pasted_text: blank_centre_paste }

      assert_response :success
      assert assigns(:attribution).blank_choice_required?
      assert_select "select[name=blank_cost_centre_id]"
      assert_select "option[value=?]", fringe_cost_centre.id.to_s
      assert_select "option[value=skip]"
      assert_select "input[type=submit][value='Apply reconciliation']", false,
                    "nothing may be applied while the question is unanswered"
    end

    test "apply refuses the whole paste while blank rows have no cost centre" do
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste }

      assert_response :success
      assert_equal 0, ::Reimbursements::EusaActual.count,
                   "importing the attributed rows and losing the rest is the silent drop this prevents"
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
      assert_match(/no cost centre of their own/, response.body)
    end

    test "a chosen cost centre imports the blank rows under it" do
      termtime = create_second_reimbursements_cost_centre
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste, blank_cost_centre_id: termtime.id.to_s }

      assert_response :success
      actuals = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal 2, actuals.size
      assert_equal [ fringe_cost_centre.id, termtime.id ], actuals.map(&:cost_centre_id),
                   "the blank row lands in the pot the operator named, not the one its neighbour used"
    end

    test "the skip choice imports the rest and drops the blank rows" do
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste,
                             blank_cost_centre_id: ::Reimbursements::ActualsAttribution::SKIP }

      assert_response :success
      assert_equal [ fringe_cost_centre.id ], ::Reimbursements::EusaActual.pluck(:cost_centre_id)
      assert_match(/skipped, as you chose/, response.body)
    end

    # --- Offsetting pairs never span cost centres --------------------------
    #
    # A false positive hides real spend from BOTH pots' rollups; a false negative leaves two visible rows.

    test "an accrual and a reversal in different cost centres are never paired" do
      create_second_reimbursements_cost_centre
      sign_in @user
      paste = [ HEADER, accrual_row, reversal_row(cost_centre: "BED") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_empty assigns(:offsetting_pairs)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    # --- Matching is scoped to the row's cost centre -----------------------

    test "rows never match an expense or income budget in another cost centre" do
      termtime = create_second_reimbursements_cost_centre
      @budget.update!(cost_centre: termtime)
      @income.update!(cost_centre: termtime)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}\n#{credit_row}" }

      assert_empty assigns(:matched_debits), "a Fringe debit must not pay a termtime claim"
      assert_empty assigns(:matched_credits)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    test "a debit row matches an expense whose budget is in its own cost centre" do
      create_second_reimbursements_cost_centre
      @budget.update!(cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
    end

    # Budget#cost_centre_id is nullable, so most budgets have none: such an expense matches only while a
    # single centre is configured (the basic match test), and once a second exists we stop guessing.
    test "an expense with no cost centre stops matching once a second centre exists" do
      create_second_reimbursements_cost_centre
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits),
                   "an unattributed expense could belong to either pot, so we no longer guess"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    # --- Dedup is per period AND per cost centre ---------------------------

    test "a stored row blocks a re-import in its own cost centre only" do
      create_second_reimbursements_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}\n#{debit_row(cost_centre: 'BED')}" }

      assert_equal %w[F40], assigns(:skipped_rows).map(&:cost_centre)
      assert_equal %w[BED], assigns(:new_rows).map(&:cost_centre),
                   "two pots can each carry the same charge in the same period"
    end

    # A stored row with no cost centre can't say which pot it is in: skipping a re-import leaves a
    # visible gap, importing a duplicate double-counts spend.
    test "a stored row with no cost centre of its own still blocks a re-import" do
      create_second_reimbursements_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(cost_centre: 'BED')}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
    end

    # The tickbox keys must survive the stateless round trip; this mimics what the preview form posts back.
    def offsetting_pair_keys(pasted_text, cost_centre: ::Reimbursements::CostCentre.default)
      rows = ::Reimbursements::Reconciliation.parse_actuals_rows(pasted_text)
      ::Reimbursements::Reconciliation
        .detect_offsetting_pairs(rows, cost_centres: rows.map { cost_centre.id.to_s })
        .map(&:key)
    end

    # --- Uploading the sheet -------------------------------------------------

    def actuals_xlsx(rows)
      require "caxlsx"
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Actuals") { |sheet| rows.each { |row| sheet.add_row row } }
      file = Tempfile.new([ "actuals", ".xlsx" ])
      file.binmode
      file.write(package.to_stream.read)
      file.rewind
      Rack::Test::UploadedFile.new(file.path,
                                   "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end

    # The OLE2 signature every legacy .xls opens with, so +name+ can lie about the format like a renamed file.
    def actuals_legacy_xls(name: "actuals.xls")
      file = Tempfile.new([ "actuals", File.extname(name) ])
      file.binmode
      file.write("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00".b * 64))
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel", original_filename: name)
    end

    # A .xlsx by name and first bytes (so not caught as legacy) that Roo still cannot open.
    def actuals_unreadable_xlsx
      file = Tempfile.new([ "actuals", ".xlsx" ])
      file.binmode
      file.write("not a zip at all")
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel",
                                   original_filename: "actuals.xlsx")
    end

    def actuals_csv(text)
      file = Tempfile.new([ "actuals", ".csv" ])
      file.write(text)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "text/csv")
    end

    # The wizard is stateless and an upload has no second file to re-send, so every form carrying the
    # sheet on to apply must hold it as TEXT (the apply form once carried params[:pasted_text], empty
    # on upload).
    test "an uploaded xlsx previews like a paste and is carried on as text" do
      sign_in @user

      post :preview, params: { actuals_file: actuals_xlsx([ HEADER.split("\t"), debit_row.split("\t") ]) }

      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
      carriers = css_select("input[name=pasted_text][type=hidden]")
      assert_not_empty carriers
      carriers.each { |field| assert_includes field["value"].to_s, "439999\tF40" }
    end

    test "a csv upload is read as the text it already is" do
      sign_in @user

      post :preview, params: { actuals_file: actuals_csv("#{HEADER}\n#{debit_row}") }

      assert_response :success
      assert_match(/Alice Producer/, response.body)
    end

    test "a submit with neither a paste nor a file says so" do
      sign_in @user

      post :preview, params: { pasted_text: "" }

      assert_response :success
      assert_match(/Paste the actuals rows, or upload the sheet/, response.body)
    end

    # An operator holding a legacy file renames it .xlsx; the raw rubyzip message (tmp path included)
    # must not leak. The CONTENT decides, not the name.
    test "an .xls renamed .xlsx is still recognised as the older format" do
      error = assert_raises(::Reimbursements::ActualsUpload::UnreadableError) do
        ::Reimbursements::ActualsUpload.to_text(actuals_legacy_xls(name: "actuals.xlsx"))
      end

      assert_match(/older \.xls/, error.message)
      assert_no_match(/tmp|Zip|zip/, error.message)
    end

    # roo 3 dropped .xls and its raw message leaked a tmp path; each raise site is pinned to state a next step.
    test "every refusal states a next step" do
      upload = ::Reimbursements::ActualsUpload

      messages = [
        assert_raises(upload::UnreadableError) { upload.to_text(actuals_legacy_xls) }.message,
        assert_raises(upload::UnreadableError) { upload.to_text(actuals_xlsx([ [] ])) }.message,
        assert_raises(upload::UnreadableError) { upload.to_text(actuals_unreadable_xlsx) }.message
      ]

      messages.each do |message|
        assert_match(/paste (the rows|them)/, message, message)
        assert_no_match(/extension option|tmp/, message, message)
        assert_no_match(/\.\./, message, "a doubled full stop: #{message}")
      end
    end

    # Every message carries its own advice, so the flash must not add a second copy.
    test "the flash states the advice once" do
      sign_in @user

      post :preview, params: { actuals_file: actuals_legacy_xls }

      message = response.body[/Couldn't read that file: [^"<]*/]
      assert_equal 1, message.scan(/paste the rows instead/).size, message
    end

    # A cell's own tab would split the row into two columns and shift every figure left, silently.
    test "a tab inside a spreadsheet cell cannot shift the row's columns" do
      # The tab has to be INSIDE one cell, which a row built by splitting on tabs would never show.
      cells = debit_row.split("\t")
      cells[5] = "Alice\tProducer"
      text = ::Reimbursements::ActualsUpload.to_text(actuals_xlsx([ HEADER.split("\t"), cells ]))

      assert_equal HEADER.split("\t").size, text.lines.last.split("\t").size
      assert_includes text, "Alice Producer", "the tab becomes a space rather than a column break"
    end
  end
  end
end
