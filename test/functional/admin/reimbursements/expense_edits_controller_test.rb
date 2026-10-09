require "test_helper"

module Admin
  module Reimbursements
    ##
    # Finance editing of an expense at any status.
    class ExpenseEditsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      EDITABLE_STATUSES = %w[Pending Approved Submitted Paid].freeze
      MC = ::Reimbursements::ModulusCheck

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: "08-99-99", account_number: "66374958")
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")

        @checker = FakeModulusChecker.new("66374958" => MC::VALID)
        ExpenseEditsController.checker_builder = -> { @checker }
      end

      teardown do
        BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
        ExpenseEditsController.checker_builder = -> { MC.default_checker }
      end

      def expense_at(status, **attrs)
        create_reimbursements_expense(person: @person, budget: @budget, status: status, **attrs)
      end

      def two_receipt_expense(status: "Approved")
        expense = expense_at(status, receipt: false)
        attach_test_receipt(expense, filename: "a.pdf")
        attach_test_receipt(expense, filename: "b.pdf")
        expense
      end

      def image_receipt_expense(status: "Approved")
        expense = expense_at(status, receipt: false)
        attach_test_receipt(expense, filename: "receipt.jpg", content_type: "image/jpeg",
                            bytes: "JPEGDATA")
        expense
      end

      # --- Index: all-expenses table with filters + search ----------------

      # Two budgets and two payees across three statuses.
      def seed_multi_expenses
        person2 = create_reimbursements_person(name: "Sam Stagehand", email: "sam@example.com",
                                               sort_code: "20-00-00", account_number: "12345678")
        @budget2 = create_reimbursements_budget(name: "Costumes", nominal_code: "4100")
        @exp1 = expense_at("Pending", auto_number: 1, description: "Fake blood",
                           payment_reference: "PROPS PAT")
        @exp2 = create_reimbursements_expense(person: person2, budget: @budget2, status: "Approved",
                                              auto_number: 2, description: "Velvet cloak",
                                              payment_reference: "COSTUMES SAM",
                                              amount: BigDecimal("99"),
                                              amount_excl_vat: BigDecimal("82.5"))
        @exp3 = expense_at("Paid", auto_number: 3, description: "Stage nails",
                           amount: BigDecimal("5"), amount_excl_vat: BigDecimal("4.17"))
      end

      def third_party_claim
        # An Invoice: the effective payee is the supplier, not @person who filed it.
        expense_at("Pending", payee_name_override: "Concord Theatricals Ltd",
                              sort_code_override: "08-99-99", account_number_override: "66374958",
                              expense_type: ::Reimbursements::Expense::TYPE_INVOICE)
      end

      def centred_budget
        create_reimbursements_budget(name: "Lights", nominal_code: "4200",
                                     cost_centre: create_second_reimbursements_cost_centre(short_code: "BF"))
      end

      test "the edit page's budget select is a Tom Select labelled with each line's centre" do
        @budget = centred_budget
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_select "select.simple-select2[name=budget_record_id]:not([class*=border])" do
          assert_select "option[selected]", text: "BF - Lights"
        end
      end

      test "the index's budget filter is a Tom Select labelled with each line's centre" do
        centred_budget
        sign_in @user

        get :index

        assert_select "select.simple-select2[name=budget]:not([class*=border]) option", text: "BF - Lights"
      end

      test "index lists every expense with a link to edit each" do
        seed_multi_expenses
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Fake blood"
        assert_includes response.body, "Velvet cloak"
        assert_includes response.body, "Stage nails"
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@exp1.record_id)
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@exp2.record_id)
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@exp3.record_id)
        assert_select "a[href=?]", admin_reimbursements_expense_import_path(cost_centre: nil),
                      text: "Import expenses"
      end

      # The wizard reads an empty cost_centre= as no centre chosen, so it still asks.
      test "Import expenses keeps an explicit All" do
        create_second_reimbursements_cost_centre
        sign_in @user

        get :index, params: { cost_centre: "" }

        assert_select "a[href=?]", admin_reimbursements_expense_import_path(cost_centre: ""), text: "Import expenses"
      end

      test "index filters and search narrow to exactly the matching claims" do
        seed_multi_expenses
        # A third-party invoice's submitter must be findable by name and email.
        claim = third_party_claim
        sign_in @user

        {
          { status: "Paid" } => [ @exp3 ],
          { budget: @budget2.record_id } => [ @exp2 ],
          { q: "velvet" } => [ @exp2 ],
          { q: "stagehand" } => [ @exp2 ],
          { q: "3" } => [ @exp3 ],
          { q: "#3" } => [ @exp3 ],
          { q: "£99.00" } => [ @exp2 ],
          { q: "not a number and no substring match" } => [],
          { q: "Pat Producer" } => [ @exp1, @exp3, claim ],
          { q: "pat@example.com" } => [ @exp1, @exp3, claim ],
          { q: "Concord" } => [ claim ]
        }.each do |params, expected|
          get :index, params: params

          assert_response :success
          assert_equal expected.map(&:record_id).sort, assigns(:expenses).map(&:record_id).sort, params.inspect
        end
      end

      # --- CSV export --------------------------------------------------------

      # The sidebar renders on every finance page, so any of them will do.
      test "the Finance sidebar links to the exports page" do
        sign_in @user

        get :index

        assert_includes response.body, "Exports"
        assert_includes response.body, "/admin/reimbursements/export"
      end

      test "index CSV export has a header row and one data row per expense" do
        seed_multi_expenses
        sign_in @user

        get :index, format: :csv

        assert_csv_download("expenses")
        rows = CSV.parse(response.body)
        assert_equal [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                       "Description", "Payment reference", "Submitted", "Needs attention",
                       "Cost centre", "Area" ], rows.first
        assert_equal 4, rows.size, "header + three expenses"
        stage = rows.find { |r| r[6] == "Stage nails" }
        assert_equal %w[3 Paid], stage.values_at(0, 1)
        assert_equal "Pat Producer", stage[2]
        assert_equal "Props", stage[3]
        assert_equal "5.0", stage[4]
      end

      test "index CSV export carries the on-screen filter, exporting only the filtered set" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { status: "Paid" }, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 2, rows.size, "header + the single Paid expense"
        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Velvet cloak"
      end

      test "index CSV export lists the full filtered set, not just the first page" do
        seed_paged_expenses(60)
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 61, rows.size, "header + all 60 expenses (pagination is display-only)"
      end

      test "index CSV export joins the needs-attention reasons" do
        # An expense with no ex-VAT amount and no budget flags two reasons.
        expense_at("Pending", budget: nil, auto_number: 7, description: "Flagged item",
                   amount_excl_vat: nil)
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        column = ::Reimbursements::Exports::Expenses::HEADERS.index("Needs attention")
        reasons = rows.find { |r| r[6] == "Flagged item" }[column]
        assert_includes reasons, "no ex-VAT amount"
        assert_includes reasons, "no budget"
      end

      # --- Pagination (50 per page, filters carry across pages) ------------

      def seed_paged_expenses(count)
        (1..count).each do |n|
          expense_at("Pending", auto_number: n, description: "Expense number #{n}",
                     receipt: false, submitted_at: Time.utc(2026, 5, (n % 28) + 1))
        end
      end

      test "index pages the list at 50, page 2 holding the next slice" do
        seed_paged_expenses(60)
        sign_in @user

        get :index
        page1 = response.body.scan(/Expense number \d+/).uniq
        assert_equal 50, page1.size
        assert_includes response.body, "60 expenses"

        get :index, params: { page: 2 }
        page2 = response.body.scan(/Expense number \d+/).uniq

        assert_equal 10, page2.size, "second page should show the remaining 10 expenses"
        assert_empty(page1 & page2, "page 2 must not repeat any page 1 rows")
      end

      test "a status filter and a page combine (filter carries onto page 2)" do
        seed_paged_expenses(60)
        (1..20).each do |n|
          expense_at("Paid", auto_number: 100 + n, description: "Paid row #{n}", receipt: false)
        end
        sign_in @user

        get :index, params: { status: "Pending", page: 2 }

        assert_response :success
        assert_includes response.body, "60 expenses"
        assert_equal 10, response.body.scan(/Expense number \d+/).uniq.size, "page 2 should show the last 10 Pending rows"
        assert_equal 0, response.body.scan(/Paid row \d+/).size, "a Paid expense must never appear under the Pending filter"
        assert_match(/[?&]status=Pending/, response.body)
      end

      # --- Needs-attention reasons tooltip ---------------------------------

      test "index flags a needs-attention expense with an accessible reasons popover" do
        # No receipt is advisory, not blocking.
        expense = expense_at("Pending", receipt: false)
        sign_in @user

        get :index

        assert_select "[data-controller='popover']" do
          assert_select "button[aria-expanded='false'][aria-controls='reasons-edits-adv-#{expense.record_id}']",
                        text: /Check first/
          assert_select "#reasons-edits-adv-#{expense.record_id} li", text: "no receipt"
        end
      end

      test "index shows a blocked expense in a distinct danger popover" do
        # No budget blocks approval.
        expense = expense_at("Pending", budget: nil)
        sign_in @user

        get :index

        assert_select "button[aria-controls='reasons-edits-block-#{expense.record_id}']", text: /Can't approve yet/
        assert_select "#reasons-edits-block-#{expense.record_id} li", text: "no budget"
      end

      test "index suppresses the attention flag on a non-actionable (Paid) row" do
        expense_at("Paid", receipt: false)
        sign_in @user

        get :index

        assert_select "[aria-controls^='reasons-edits-']", count: 0
      end

      # The Flags column is blank on Submitted/Paid/Rejected rows, so the filter
      # must not list them.
      test "the needs-attention filter lists only rows that show a flag" do
        flagged = expense_at("Pending", receipt: false)
        expense_at("Paid", receipt: false)
        sign_in @user

        get :index, params: { attention: "1" }

        assert_equal [ flagged.record_id ], assigns(:expenses).map(&:record_id)
      end

      test "index does not flag a clean expense" do
        expense_at("Pending")
        sign_in @user

        get :index

        assert_select "[aria-controls^='reasons-edits-']", count: 0
      end

      test "edit lists advisory reasons separately from blocking ones" do
        # No receipt is advisory; no budget is blocking.
        expense = expense_at("Pending", receipt: false, budget: nil)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/can't be approved until these are fixed/i, response.body)
        assert_match(/worth checking before approving/i, response.body)
        assert_includes response.body, "no receipt"
        assert_includes response.body, "no budget"
      end

      test "a clean Pending claim's edit page carries no advice, history or already-processed note" do
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_no_match(/can't be approved until these are fixed/i, response.body)
        assert_no_match(/worth checking before approving/i, response.body)
        assert_no_match(/Owner sign-off/, response.body)
        assert_no_match(/In batch/, response.body)
        assert_no_match(/Already (sent to EUSA|paid)\./, response.body)
      end

      # --- Finance can fix the payment rail ---------------------------------

      INTERNATIONAL = ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL
      UK_BACS = ::Reimbursements::Expense::PAYMENT_METHOD_UK_BACS

      def international_claim(status: "Pending", **attrs)
        expense_at(status, payment_method: INTERNATIONAL, foreign_currency: "EUR",
                           foreign_amount: BigDecimal("640"),
                           payee_name_override: "Studio Bühne", iban_override: "DE89370400440532013000",
                           bic_override: "DEUTDEFF", **attrs)
      end

      # The full stored field set, so changing one field does not blank the rest.
      def edit_params(expense, **overrides)
        { id: expense.record_id, amount: expense.amount, amount_excl_vat: expense.amount_excl_vat,
          description: expense.description, payment_reference: expense.payment_reference,
          expense_type: expense.expense_type, budget_record_id: expense.budget&.record_id,
          payment_method: expense.payment_method,
          payee_name_override: expense.payee_name_override,
          sort_code_override: expense.sort_code_override,
          account_number_override: expense.account_number_override,
          iban_override: expense.iban_override, bic_override: expense.bic_override,
          foreign_currency: expense.foreign_currency,
          foreign_amount: expense.foreign_amount }.merge(overrides)
      end

      test "edit offers the rail while the money can still move" do
        expense = expense_at("Approved")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_select "select#payment_method"
        # Both pairs are rendered so the browser can switch rails.
        assert_select "[data-reimbursements-receipt-target=ukFields]"
        assert_select "[data-reimbursements-receipt-target=internationalFields]"
      end

      %w[Submitted Paid].each do |status|
        test "edit does not offer the rail on a #{status} claim" do
          expense = expense_at(status)
          sign_in @user

          get :edit, params: { id: expense.record_id }

          assert_select "select#payment_method", false
        end

        test "a posted rail is ignored on a #{status} claim" do
          expense = expense_at(status)
          sign_in @user

          patch :update, params: edit_params(expense, payment_method: INTERNATIONAL)

          assert_equal UK_BACS, expense.reload.payment_method
        end
      end

      test "finance switches a claim onto the international rail, keeping the UK pair" do
        # EffectivePayee reads only the active pair, so the dormant one is
        # inert, and wiping it could not be undone.
        expense = expense_at("Pending", sort_code_override: "08-99-99",
                                        account_number_override: "66374958",
                                        payee_name_override: "Studio Buehne")
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: INTERNATIONAL,
                                                    iban_override: "DE89370400440532013000",
                                                    bic_override: "DEUTDEFF",
                                                    foreign_currency: "EUR", foreign_amount: "640")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert expense.international?
        assert_equal "DE89370400440532013000", expense.iban_override
        assert_equal "08-99-99", expense.sort_code_override, "the UK pair survives the switch"
        assert_equal "66374958", expense.account_number_override
      end

      test "the override rule reads the rail being posted, not the one being left" do
        # Reading the stored rail would check the sort-code pair being left.
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: INTERNATIONAL,
                                                    payee_name_override: "Studio Buehne",
                                                    iban_override: "", bic_override: "",
                                                    foreign_currency: "EUR")

        assert_response :unprocessable_content
        assert_match(/payee name, IBAN and BIC/, response.body)
        assert_not expense.reload.international?, "nothing was written"
      end

      # --- An international claim with no GBP amount is still editable ------

      test "an international claim with a blank GBP amount saves" do
        # Finance types the GBP figure at review, so the claim sits without one.
        expense = international_claim(amount: nil, amount_excl_vat: nil)
        sign_in @user

        patch :update, params: edit_params(expense, amount: "", amount_excl_vat: "",
                                                    foreign_currency: "USD")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal "USD", expense.reload.foreign_currency
      end

      test "a UK claim still needs a GBP amount" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, amount: "", description: "Edited")

        assert_response :unprocessable_content
        assert_match(/valid amount greater than 0/, response.body)
        assert_equal "Fake blood", expense.reload.description, "nothing was written"
      end

      # --- Blanking the invoice amount ---------------------------------------

      test "blanking the invoice amount clears it rather than silently reverting" do
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, foreign_amount: "")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_nil expense.reload.foreign_amount,
                   "a blank used to be ignored, and the field came back with 640.0 still in it"
      end

      test "an unreadable invoice amount is refused with the field named" do
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, foreign_amount: "six hundred")

        assert_response :unprocessable_content
        assert_match(/Invoice amount/, response.body)
        assert_equal BigDecimal("640"), expense.reload.foreign_amount, "nothing was written"
      end

      test "a UK-rail save leaves a stored invoice figure alone" do
        # The UK form does not post the field.
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: UK_BACS,
                                                    sort_code_override: "08-99-99",
                                                    account_number_override: "66374958")
                       .except(:foreign_amount, :foreign_currency)

        expense.reload
        assert_not expense.international?
        assert_equal BigDecimal("640"), expense.foreign_amount, "switching back restores the claim"
        assert_equal "EUR", expense.foreign_currency
      end

      # --- History: the claim says what happened to it ----------------------

      test "edit names the owner who signed the claim off, and when" do
        expense = expense_at("Approved")
        owner = create_reimbursements_person(name: "Olga Owner", email: "olga@example.com")
        ::Reimbursements::OwnerEndorsement.create!(
          expense_record_id: expense.record_id, budget_record_id: @budget.record_id,
          endorsed_by_person_id: owner.record_id, endorsed_amount: expense.amount,
          endorsed_at: Time.zone.parse("2026-09-01 10:00")
        )
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/Owner sign-off/, response.body)
        assert_match(/Olga Owner/, response.body)
        assert_match(/2026-09-01/, response.body)
      end

      test "edit shows a finance override with its note, which was write-only before" do
        expense = expense_at("Approved")
        ::Reimbursements::OwnerEndorsement.create!(
          expense_record_id: expense.record_id, budget_record_id: @budget.record_id,
          overridden_by: @user, note: "Owner has no portal account",
          endorsed_amount: expense.amount, endorsed_at: Time.zone.parse("2026-09-02 10:00")
        )
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/Owner sign-off overridden/, response.body)
        assert_match(/Owner has no portal account/, response.body)
        assert_match(/2026-09-02/, response.body)
      end

      test "edit shows the rejection reason, which was stored and rendered nowhere" do
        expense = expense_at("Rejected", rejection_reason: "No receipt attached",
                                         rejection_notified: Time.zone.parse("2026-09-03 10:00"))
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/No receipt attached/, response.body)
        assert_match(/producer emailed/, response.body)
      end

      test "edit names the batch a claim is in, linked, with its BACS date" do
        batch = create_reimbursements_batch(name: "May run", date_sent: Date.new(2026, 5, 13))
        expense = expense_at("Submitted", batch: batch)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_select "a[href=?]", admin_reimbursements_batch_path(batch.record_id), text: "May run"
        assert_match(/BACS 2026-05-13/, response.body)
        assert_no_match(/Sent 2026-05-13/, response.body)
      end

      test "edit shows the payment-confirmed date on a Paid claim" do
        expense = expense_at("Paid", payment_confirmed_date: Date.new(2026, 6, 1))
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/Payment confirmed/, response.body)
        assert_match(/2026-06-01/, response.body)
      end

      # --- Paid to and submitted by ---------------------------------------

      test "index names both columns: paid to, and submitted by" do
        third_party_claim
        sign_in @user

        get :index

        assert_response :success
        assert_match(/Paid to/, response.body)
        assert_match(/Submitted by/, response.body)
        assert_no_match(/>Payee</, response.body)
      end

      test "index filters to one person's claims with ?person=" do
        mine = expense_at("Pending")
        other_person = create_reimbursements_person(name: "Other Person", email: "other@example.com")
        theirs = create_reimbursements_expense(person: other_person, budget: @budget, status: "Pending")
        sign_in @user

        get :index, params: { person: @person.record_id }

        ids = assigns(:expenses).map(&:record_id)
        assert_includes ids, mine.record_id
        assert_not_includes ids, theirs.record_id
        assert_match(/Showing only the claims submitted by/, response.body)
      end

      test "edit gives approval advice on an Approved claim, and none on a settled one" do
        approved = expense_at("Approved", receipt: false, budget: nil)
        paid = expense_at("Paid", receipt: false, budget: nil)
        sign_in @user

        get :edit, params: { id: approved.record_id }
        assert_match(/can't be approved until these are fixed/i, response.body)

        # On a Paid claim it is advice about a decision nobody will take again.
        get :edit, params: { id: paid.record_id }
        assert_response :success
        assert_no_match(/can't be approved until these are fixed/i, response.body)
        assert_no_match(/worth checking before approving/i, response.body)
        assert_match(/already paid/i, response.body)
      end

      # --- Update at every status ------------------------------------------

      EDITABLE_STATUSES.each do |status|
        test "update persists edits for a #{status} expense via update_expense!" do
          expense = expense_at(status)
          sign_in @user

          patch :update, params: { id: expense.record_id, amount: "42.00", amount_excl_vat: "35.00",
                                   description: "Edited #{status}", payment_reference: "REF-#{status}",
                                   nominal_code_override: "4100", budget_record_id: @budget.record_id,
                                   payee_name_override: "Acme Ltd", sort_code_override: "20-00-00",
                                   account_number_override: "12345678" }

          assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
          expense.reload
          assert_equal BigDecimal("42"), expense.amount
          assert_equal BigDecimal("35"), expense.amount_excl_vat
          assert_equal "Edited #{status}", expense.description
          assert_equal "REF-#{status}", expense.payment_reference
          assert_equal "4100", expense.nominal_code_override
          assert_equal "Acme Ltd", expense.payee_name_override
          assert_equal "20-00-00", expense.sort_code_override
          assert_equal "12345678", expense.account_number_override
          assert_equal status, expense.status
        end
      end

      # The PARSED value must be written: AR casts a string to a decimal column
      # with to_d, which reads "£1,200" as 0.
      test "update accepts a currency-formatted amount and stores the parsed number" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, amount: "£1,200.50", amount_excl_vat: "£1,000")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert_equal BigDecimal("1200.50"), expense.amount
        assert_equal BigDecimal("1000"), expense.amount_excl_vat
      end

      test "update leaves excl VAT untouched when zero is submitted" do
        expense = expense_at("Paid")
        sign_in @user

        patch :update, params: edit_params(expense, amount: "20.00", amount_excl_vat: "0")

        assert_equal BigDecimal("10.42"), expense.reload.amount_excl_vat
      end

      # --- Expense type ----------------------------------------------------

      # From EUSA is settable only here.
      test "update re-types a claim, including to finance's own From EUSA" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, expense_type: ::Reimbursements::Expense::TYPE_FROM_EUSA)

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, expense.reload.expense_type
      end

      test "update rejects an expense type that isn't one of ours" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, expense_type: "Petty cash")

        assert_response :unprocessable_content
        assert_match(/unknown expense type/i, response.body)
        assert_equal "Reimbursement", expense.reload.expense_type, "nothing was written"
      end

      # With no overrides EffectivePayee falls back to the submitter's own
      # details, so the Invoice would pay them.
      test "update rejects switching a payable claim to Invoice with no payee overrides" do
        expense = expense_at("Approved")
        sign_in @user

        patch :update, params: edit_params(expense, expense_type: ::Reimbursements::Expense::TYPE_INVOICE)

        assert_response :unprocessable_content
        assert_match(/would pay Pat Producer/i, response.body)
        assert_equal "Reimbursement", expense.reload.expense_type, "nothing was written"
      end

      test "update accepts Invoice once the payee overrides are filled in" do
        expense = expense_at("Approved")
        sign_in @user

        patch :update, params: edit_params(expense, expense_type: ::Reimbursements::Expense::TYPE_INVOICE,
                                                    payee_name_override: "Acme Ltd",
                                                    sort_code_override: "20-00-00",
                                                    account_number_override: "12345678")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal ::Reimbursements::Expense::TYPE_INVOICE, expense.reload.expense_type
      end

      # Settled claims stay re-typable without invented supplier details.
      %w[Submitted Paid].each do |status|
        test "update re-types an already-processed #{status} claim to Invoice without overrides" do
          expense = expense_at(status)
          sign_in @user

          patch :update, params: edit_params(expense, expense_type: ::Reimbursements::Expense::TYPE_INVOICE)

          assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
          assert_equal ::Reimbursements::Expense::TYPE_INVOICE, expense.reload.expense_type
        end
      end

      # Other forms posting here send no expense_type.
      test "update leaves the type alone when the field isn't posted" do
        expense = expense_at("Pending", expense_type: ::Reimbursements::Expense::TYPE_INVOICE,
                                        payee_name_override: "Acme Ltd",
                                        sort_code_override: "20-00-00",
                                        account_number_override: "12345678")
        sign_in @user

        patch :update, params: edit_params(expense).except(:expense_type)

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal ::Reimbursements::Expense::TYPE_INVOICE, expense.reload.expense_type
      end

      test "edit renders the type select with the current type chosen" do
        expense = expense_at("Pending", expense_type: ::Reimbursements::Expense::TYPE_INVOICE)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_select "select#expense_type option[selected][value=?]",
                      ::Reimbursements::Expense::TYPE_INVOICE
        assert_select "select#expense_type option", text: ::Reimbursements::Expense::TYPE_FROM_EUSA
      end

      test "update rejects a budget_record_id that doesn't resolve to a real budget" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, budget_record_id: "999999999", description: "Edited")

        assert_response :unprocessable_content
        assert_match(/budget no longer exists/i, response.body)
        assert_equal "Fake blood", expense.reload.description, "nothing was written"
      end

      # --- The international rail ---------------------------------------------

      # The UK trio rule must not refuse an international claim.
      test "update saves an international claim's bank details, invoice amount and currency" do
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, iban_override: "NL91 ABNA 0417 1643 00",
                                                    bic_override: " abnanl2a ",
                                                    foreign_amount: "500.00", foreign_currency: "USD")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert_equal "NL91ABNA0417164300", expense.iban_override
        assert_equal "ABNANL2A", expense.bic_override
        assert_equal BigDecimal("500"), expense.foreign_amount
        assert_equal "USD", expense.foreign_currency
        assert_equal "Studio Bühne", expense.payee_name_override
      end

      # The last point anything checks the number before EUSA's bank acts on it.
      test "update refuses bad international overrides and writes nothing" do
        expense = international_claim
        sign_in @user

        {
          { iban_override: "DE88 3704 0044 0532 0130 00" } => /Payee IBAN must be/,
          { bic_override: "DEUTDEFF5" } => /Payee BIC must be/,
          { foreign_currency: "XYZ" } => /Payment currency must be/,
          { bic_override: "" } => /all three/
        }.each do |bad, message|
          patch :update, params: edit_params(expense, **bad)

          assert_response :unprocessable_content
          assert_match message, response.body, bad.inspect
          expense.reload
          assert_equal [ "DE89370400440532013000", "DEUTDEFF", "EUR" ],
                       [ expense.iban_override, expense.bic_override, expense.foreign_currency ], bad.inspect
        end
      end

      # Its supplier details may never have been captured.
      test "update leaves a Paid international claim editable with blank overrides" do
        expense = international_claim(status: "Paid", payee_name_override: "",
                                      iban_override: "", bic_override: "")
        sign_in @user

        patch :update, params: edit_params(expense)

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
      end

      test "update refuses bad UK overrides and writes nothing" do
        expense = expense_at("Pending")
        sign_in @user

        {
          { sort_code_override: "20-00-0X" } => /Sort code override must be/,
          { account_number_override: "1234" } => /Account number override must be/,
          { account_number_override: "" } => /fill in all three/
        }.each do |bad, message|
          patch :update, params: edit_params(expense, payee_name_override: "Acme Ltd",
                                                      sort_code_override: "20-00-00",
                                                      account_number_override: "12345678", **bad)

          assert_response :unprocessable_content
          assert_match message, response.body, bad.inspect
          assert_nil expense.reload.sort_code_override, bad.inspect
        end
      end

      test "update allows blank bank-detail overrides (no override, fall back to the payee's own)" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, sort_code_override: "", account_number_override: "")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert_equal "", expense.sort_code_override
        assert_equal "", expense.account_number_override
      end

      # --- Already-sent / already-paid note --------------------------------

      test "shows an already-sent-to-EUSA note for a Submitted expense" do
        expense = expense_at("Submitted")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/already sent to EUSA/i, response.body)
      end

      test "editing an unknown expense 404s" do
        sign_in @user

        get :edit, params: { id: "999999999" }

        assert_response :not_found
      end

      # --- Receipts --------------------------------------------------------

      test "edit renders an image receipt as a fancybox thumbnail keyed to the expense" do
        expense = image_receipt_expense
        sign_in @user

        get :edit, params: { id: expense.record_id }

        receipt = expense.receipts.sole
        assert_includes response.body, 'data-controller="fancybox receipt-viewer"'
        assert_includes response.body, "data-fancybox=\"receipts-#{expense.record_id}\""
        # The lightbox link opens the full image; the thumbnail previews it.
        assert_includes response.body, receipt.url
        assert_includes response.body, receipt.preview_url
      end

      # ActiveStorage renders a PDF's first page, so it gets a real thumbnail.
      # The only new-tab link is the labelled fallback inside the viewer pane.
      test "edit previews a PDF receipt and opens it in an in-page frame" do
        expense = two_receipt_expense
        sign_in @user

        get :edit, params: { id: expense.record_id }

        first, second = expense.receipts
        assert_match(/<img[^>]+src="#{Regexp.escape(first.preview_url)}"/, response.body)
        assert_match(/<img[^>]+src="#{Regexp.escape(second.preview_url)}"/, response.body)
        assert_match(/<iframe[^>]+data-src="#{Regexp.escape(first.url)}"/, response.body)
        assert_match(/<iframe[^>]+title="Receipt: a\.pdf"/, response.body)
        assert_select "button[data-action='receipt-viewer#show']", 2
        new_tab_links = css_select("a[target=_blank]")
                        .select { |link| link["href"].to_s.match?(%r{/receipts/\d+/inline\z}) }
        assert_equal 2, new_tab_links.size, "only the per-receipt new-tab fallback may remain"
        new_tab_links.each { |link| assert_match(/\AOpen [ab]\.pdf in a new tab\z/, link["aria-label"]) }
      end

      # Sheet music and Office documents are allow-listed uploads that no browser
      # can render: they must offer a download, never an empty frame.
      test "edit degrades an unrenderable receipt to a download link" do
        expense = expense_at("Approved", receipt: false)
        attach_test_receipt(expense, filename: "score.mscz", content_type: "application/x-musescore",
                            bytes: "PK")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_includes response.body, "score.mscz can't be shown in the browser."
        assert_includes response.body, 'aria-label="Download score.mscz"'
        assert_no_match(/<iframe/, response.body)
        # No thumbnail exists, so the strip shows the document icon.
        assert_includes response.body, "fa-file-lines"
      end

      test "edit offers the finance dropzone and a remove control per receipt" do
        expense = two_receipt_expense
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_select "[data-controller='receipts-upload'][data-receipts-upload-url-value=?]",
                      admin_reimbursements_expense_edit_receipts_path(expense.record_id)
        assert_select "button[data-action='receipts-upload#remove']", 2
        # The remove controls hit the FINANCE route, not the producer's own.
        assert_select "button[data-url^=?]",
                      "#{edit_admin_reimbursements_expense_edit_path(expense.record_id).delete_suffix('/edit')}/receipts/",
                      2
      end

      test "remove_receipt as a turbo stream replaces the gallery with finance remove controls" do
        expense = two_receipt_expense
        removed = expense.receipt_files.find { |file| file.filename.to_s == "a.pdf" }
        sign_in @user

        delete :remove_receipt, params: { id: expense.record_id, attachment_id: removed.blob_id.to_s },
                                format: :turbo_stream

        assert_response :success
        assert_includes response.body, 'turbo-stream action="replace" target="receipts-gallery"'
        assert_select "button[data-action='receipts-upload#remove']", 1
        assert_includes response.body, "/receipts/"
        assert_equal [ "b.pdf" ], expense.reload.receipt_files.map { |file| file.filename.to_s }
      end

      test "add_receipts as a turbo stream replaces the gallery" do
        expense = expense_at("Paid")
        sign_in @user

        assert_difference -> { expense.receipt_files.count }, 1 do
          post :add_receipts, params: { id: expense.record_id,
                                        receipts: [ fixture_file_upload("reimbursements_receipt.pdf", "application/pdf") ] },
                              format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, 'turbo-stream action="replace" target="receipts-gallery"'
      end

      test "add_receipts with no file attaches nothing and says so" do
        expense = expense_at("Paid")
        sign_in @user

        assert_no_difference -> { expense.receipt_files.count } do
          post :add_receipts, params: { id: expense.record_id }, format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, ERB::Util.html_escape(AttachesReceipts::NOTHING_USABLE)
      end

      # The checker returns INVALID for a blank pair, which drew "likely a typo"
      # under "no bank details".
      test "no modulus banner for a claim with no bank details" do
        payee = create_reimbursements_person(name: "No Bank", email: "nobank@example.com",
                                             sort_code: "", account_number: "")
        expense = create_reimbursements_expense(person: payee, budget: @budget, status: "Approved")

        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_match(/no bank details/i, response.body,
                     "the real problem must still be stated")
        assert_no_match(/Modulus check failed/, response.body,
                        "a blank pair is not a typo")
      end

      # --- Changing the payee -------------------------------------------------

      def other_payee
        create_reimbursements_person(name: "Robin Rig", email: "robin@example.com",
                                     sort_code: "08-99-99", account_number: "12345678")
      end

      test "the edit form offers every registered person as the payee" do
        other = other_payee
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_select "select[name=person_record_id] option[value=?]", other.record_id
        assert_select "select[name=person_record_id] option[value=?]", @person.record_id
      end

      # Paid included, unlike the rail and the type: imported claims already
      # Paid to the wrong payee are what this exists for.
      %w[Pending Paid].each do |status|
        test "saving a different payee re-points a #{status} claim" do
          other = other_payee
          expense = expense_at(status)
          sign_in @user

          patch :update, params: edit_params(expense, person_record_id: other.record_id)

          assert_equal other.id, expense.reload.person_id
        end
      end

      test "a payee id the page never offered is refused rather than 500ing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, person_record_id: "999999")

        assert_response :unprocessable_content
        assert_match(/no longer in the registry/, response.body)
        assert_equal @person.id, expense.reload.person_id
      end

      test "a blank payee leaves the claim with the one it has" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: edit_params(expense, person_record_id: "")

        assert_equal @person.id, expense.reload.person_id,
                     "a claim with no payee at all is the state the BACS pre-flight refuses"
      end

      # --- Reopening a rejected claim -----------------------------------------

      # Never straight to Approved, so reopening is no way round the owner gate.
      test "a rejected claim can be put back in the queue" do
        expense = expense_at("Rejected", rejection_reason: "No receipt attached")
        sign_in @user

        post :reopen, params: { id: expense.record_id }

        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status
      end

      test "reopening keeps the rejection in the claim's history" do
        expense = expense_at("Rejected", rejection_reason: "No receipt attached",
                             rejection_notified: Time.current)
        sign_in @user

        post :reopen, params: { id: expense.record_id }
        get :edit, params: { id: expense.record_id }

        assert_match(/No receipt attached/, response.body)
        assert_match(/reopened since/, response.body,
                     "the reason must read as history, not as the claim's state")
      end

      test "only a rejected claim can be reopened" do
        expense = expense_at("Paid")
        sign_in @user

        post :reopen, params: { id: expense.record_id }

        assert_match(/Only a rejected claim/, flash[:alert])
        assert_equal ::Reimbursements::Status::PAID, expense.reload.status
      end

      test "the Reopen control is offered on a rejected claim and nowhere else" do
        rejected = expense_at("Rejected", rejection_reason: "No receipt")
        paid = expense_at("Paid")
        sign_in @user

        get :edit, params: { id: rejected.record_id }
        assert_select "form[action=?]",
                      admin_reimbursements_reopen_expense_edit_path(rejected.record_id)

        get :edit, params: { id: paid.record_id }
        assert_select "form[action=?]",
                      admin_reimbursements_reopen_expense_edit_path(paid.record_id), count: 0
      end
    end
  end
end
