require "test_helper"

module Admin
  module Reimbursements
    ##
    # The finance-only "edit an expense at ANY status" surface. Unlike the
    # producer portal (Pending/Draft only) and unlike the Review queue
    # (Pending inline), this lets the Business Manager view and edit an
    # expense whatever its status — including Submitted and Paid — reachable
    # from the Review cards and by a lookup on auto-number/record id.
    class ExpenseEditsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      EDITABLE_STATUSES = %w[Pending Approved Submitted Paid].freeze
      MC = ::Reimbursements::ModulusCheck

      FakeChecker = ReimbursementsTestHelpers::FakeModulusChecker

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: "08-99-99", account_number: "66374958")
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")

        @checker = FakeChecker.new("66374958" => MC::VALID)
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

      # --- Auth gating -----------------------------------------------------

      test "requires sign-in" do
        expense = expense_at("Pending")
        get :edit, params: { id: expense.record_id }
        assert_redirected_to new_user_session_path
      end

      test "the producer portal permission alone does not grant finance access" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        expense = expense_at("Pending")
        sign_in other

        get :edit, params: { id: expense.record_id }

        assert_response :forbidden
      end

      # --- Index: all-expenses table with filters + search ----------------

      # Two budgets and two payees across three statuses, so the filter/search
      # tests can prove narrowing (and exclusion).
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

      test "index requires the finance permission (producer access alone is forbidden)" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        sign_in other

        get :index

        assert_response :forbidden
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
      end

      test "index status filter narrows to a single status" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { status: "Paid" }

        assert_response :success
        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Velvet cloak"
      end

      test "index budget filter narrows to a single budget" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { budget: @budget2.record_id }

        assert_response :success
        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Stage nails"
      end

      test "index search matches a description substring and excludes non-matches" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { q: "velvet" }

        assert_response :success
        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Stage nails"
      end

      test "index search matches the effective payee name" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { q: "stagehand" }

        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search matches an exact auto-number" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { q: "3" }

        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search matches a numeric amount, stripping a £ prefix and commas" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { q: "£99.00" }

        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search with a non-numeric, non-matching query returns no rows without raising" do
        seed_multi_expenses
        sign_in @user

        get :index, params: { q: "not a number and no substring match" }

        assert_response :success
        assert_not_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
      end

      # --- CSV export --------------------------------------------------------

      # The combined workbook hangs off the Finance sidebar, which renders on
      # every finance page — so any of them proves the link is reachable.
      test "the Finance sidebar links to the exports page" do
        sign_in @user

        get :index

        assert_includes response.body, "Exports"
        assert_includes response.body, "/admin/reimbursements/export"
      end

      test "index CSV export answers a text/csv download named for today" do
        seed_multi_expenses
        sign_in @user

        get :index, format: :csv

        assert_csv_download("expenses")
      end

      test "index CSV export has a header row and one data row per expense" do
        seed_multi_expenses
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                       "Description", "Payment reference", "Submitted", "Needs attention",
                       "Cost centre", "Area" ], rows.first
        assert_equal 4, rows.size, "header + three expenses"
        # A concrete data row: the Paid "Stage nails" expense to Pat, £5.00, Props.
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

      test "index CSV export neutralises formula-injected submitter text" do
        # A description a submitter controls entirely: on CSV re-import Excel
        # would execute a leading "=" as a formula.
        expense_at("Pending", auto_number: 9, description: "=HYPERLINK(\"http://evil\",\"click\")")
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        injected = rows.find { |r| r[0] == "9" }
        assert_equal "'=HYPERLINK(\"http://evil\",\"click\")", injected[6]
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

      # Build `count` Pending expenses, newest first by submitted_at so the
      # ordering (and therefore which slice lands on which page) is deterministic.
      def seed_paged_expenses(count)
        (1..count).each do |n|
          expense_at("Pending", auto_number: n, description: "Expense number #{n}",
                     receipt: false, submitted_at: Time.utc(2026, 5, (n % 28) + 1))
        end
      end

      test "index pages the list at 50 per page" do
        seed_paged_expenses(60)
        sign_in @user

        get :index
        page1_rows = response.body.scan(/Expense number \d+/).uniq.size
        assert_equal 50, page1_rows, "first page should show 50 of 60 expenses"
        assert_includes response.body, "60 expenses"
      end

      test "index page 2 returns the next slice, not page 1's rows" do
        seed_paged_expenses(60)
        sign_in @user

        get :index
        page1 = response.body.scan(/Expense number \d+/).uniq

        get :index, params: { page: 2 }
        page2 = response.body.scan(/Expense number \d+/).uniq

        assert_equal 10, page2.size, "second page should show the remaining 10 expenses"
        assert_empty(page1 & page2, "page 2 must not repeat any page 1 rows")
      end

      test "a status filter and a page combine (filter carries onto page 2)" do
        # 60 Pending + 20 Paid; filtering to Pending leaves 60 (two pages), so
        # page 2 holds the Pending remainder and never leaks a Paid expense.
        (1..60).each do |n|
          expense_at("Pending", auto_number: n, description: "Pending row #{n}",
                     receipt: false, submitted_at: Time.utc(2026, 5, (n % 28) + 1))
        end
        (1..20).each do |n|
          expense_at("Paid", auto_number: 100 + n, description: "Paid row #{n}", receipt: false)
        end
        sign_in @user

        get :index, params: { status: "Pending", page: 2 }

        assert_response :success
        assert_includes response.body, "60 expenses"
        assert_equal 10, response.body.scan(/Pending row \d+/).uniq.size, "page 2 should show the last 10 Pending rows"
        assert_equal 0, response.body.scan(/Paid row \d+/).size, "a Paid expense must never appear under the Pending filter"
        # The Pending filter must survive onto the pager links.
        assert_match(/[?&]status=Pending/, response.body)
      end

      # --- Needs-attention reasons tooltip ---------------------------------

      test "index flags a needs-attention expense with an accessible reasons popover" do
        # No receipt is an advisory (non-blocking) reason -> the amber "Check
        # first" popover.
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
        # No budget hard-blocks approval -> the red "Can't approve yet" popover,
        # separate from any advisory one.
        expense = expense_at("Pending", budget: nil)
        sign_in @user

        get :index

        assert_select "button[aria-controls='reasons-edits-block-#{expense.record_id}']", text: /Can't approve yet/
        assert_select "#reasons-edits-block-#{expense.record_id} li", text: "no budget"
      end

      test "index suppresses the attention flag on a non-actionable (Paid) row" do
        # Paid is done — the same flag there is noise. It must not render even
        # though the expense would otherwise be flagged (no receipt).
        expense_at("Paid", receipt: false)
        sign_in @user

        get :index

        assert_select "[aria-controls^='reasons-edits-']", count: 0
      end

      test "index does not flag a clean expense" do
        expense_at("Pending")
        sign_in @user

        get :index

        assert_select "[aria-controls^='reasons-edits-']", count: 0
      end

      test "edit lists advisory reasons separately from blocking ones" do
        # No receipt = advisory; no budget = blocking. Both should show, each in
        # its own section.
        expense = expense_at("Pending", receipt: false, budget: nil)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/can't be approved until these are fixed/i, response.body)
        assert_match(/worth checking before approving/i, response.body)
        assert_includes response.body, "no receipt"
        assert_includes response.body, "no budget"
      end

      test "edit shows no attention list for a clean expense" do
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_no_match(/can't be approved until these are fixed/i, response.body)
        assert_no_match(/worth checking before approving/i, response.body)
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

      # The full set of fields the form posts, so a test changing one thing
      # does not accidentally blank the rest.
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
        # Both pairs are in the markup so the browser can switch without a
        # round trip; only one is visible.
        assert_select "[data-reimbursements-receipt-target=ukFields]"
        assert_select "[data-reimbursements-receipt-target=internationalFields]"
      end

      %w[Submitted Paid].each do |status|
        test "edit does not offer the rail on a #{status} claim" do
          # The paperwork EUSA acted on has gone out; the stored rail is a
          # record of what happened, not a choice.
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

      test "finance switches a claim onto the international rail" do
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
      end

      test "a rail switch keeps the other rail's details, so it can be switched back" do
        # They are encrypted bank details a human typed, and EffectivePayee only
        # ever reads the ACTIVE rail's pair — so a dormant pair is inert, while
        # wiping it on a mis-click could not be undone.
        expense = expense_at("Pending", sort_code_override: "08-99-99",
                                        account_number_override: "66374958",
                                        payee_name_override: "Studio Buehne")
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: INTERNATIONAL,
                                                    iban_override: "DE89370400440532013000",
                                                    bic_override: "DEUTDEFF",
                                                    foreign_currency: "EUR", foreign_amount: "640")

        expense.reload
        assert_equal "08-99-99", expense.sort_code_override, "the UK pair survives the switch"
        assert_equal "66374958", expense.account_number_override
      end

      test "switching back to UK keeps the invoice figure and its currency" do
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: UK_BACS,
                                                    sort_code_override: "08-99-99",
                                                    account_number_override: "66374958")

        expense.reload
        assert_not expense.international?
        assert_equal BigDecimal("640"), expense.foreign_amount, "nothing reads it off a UK claim, " \
                                                                "and switching back restores the claim"
        assert_equal "EUR", expense.foreign_currency
      end

      test "the override rule reads the rail being posted, not the one being left" do
        # A UK claim switched to international with only a payee name must be
        # refused for the IBAN and BIC it now needs — reading the STORED rail
        # would check the sort-code pair it is walking away from.
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
        # The submitter enters the invoice figure and finance types the GBP
        # equivalent at review, so the claim legitimately sits without one.
        # The flat "Enter a valid amount greater than 0." refused every such
        # edit, naming none of the page's three amount fields.
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

        patch :update, params: edit_params(expense, amount: "")

        assert_response :unprocessable_content
        assert_match(/valid amount greater than 0/, response.body)
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
        # The UK form does not offer the field, so a post that omits it must
        # not wipe a figure the claim gets back if it is switched.
        expense = international_claim
        sign_in @user

        patch :update, params: edit_params(expense, payment_method: UK_BACS,
                                                    sort_code_override: "08-99-99",
                                                    account_number_override: "66374958")
                       .except(:foreign_amount, :foreign_currency)

        expense.reload
        assert_equal BigDecimal("640"), expense.foreign_amount
        assert_equal "EUR", expense.foreign_currency
      end

      # --- History: the claim says what happened to it ----------------------

      test "edit shows nothing but the submission for a fresh claim" do
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_no_match(/Owner sign-off/, response.body)
        assert_no_match(/In batch/, response.body)
      end

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

      # --- Search finds the submitter, not only the payee -------------------

      def third_party_claim
        # An Invoice: the EFFECTIVE payee is the supplier, and @person — who
        # actually filed it — appears nowhere the old search looked.
        expense_at("Pending", payee_name_override: "Concord Theatricals Ltd",
                              sort_code_override: "08-99-99", account_number_override: "66374958",
                              expense_type: ::Reimbursements::Expense::TYPE_INVOICE)
      end

      test "index search matches the submitter's name" do
        claim = third_party_claim
        sign_in @user

        get :index, params: { q: "Pat Producer" }

        assert_includes assigns(:expenses).map(&:record_id), claim.record_id,
                        "the submitter of a third-party invoice must be findable by name"
      end

      test "index search matches the submitter's email" do
        claim = third_party_claim
        sign_in @user

        get :index, params: { q: "pat@example.com" }

        assert_includes assigns(:expenses).map(&:record_id), claim.record_id
      end

      test "index search still matches the effective payee" do
        claim = third_party_claim
        sign_in @user

        get :index, params: { q: "Concord" }

        assert_includes assigns(:expenses).map(&:record_id), claim.record_id
      end

      test "index names both columns: paid to, and submitted by" do
        third_party_claim
        sign_in @user

        get :index

        assert_response :success
        assert_match(/Paid to/, response.body)
        assert_match(/Submitted by/, response.body)
        assert_no_match(/>Payee</, response.body)
      end

      test "the Expenses CSV export is unchanged by the on-screen column rename" do
        # An export is a stable contract: a saved formula keys off the header.
        assert_includes ::Reimbursements::Exports::Expenses::HEADERS, "Payee"
        assert_not_includes ::Reimbursements::Exports::Expenses::HEADERS, "Paid to"
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

      test "edit gives no approval advice on a settled claim" do
        # A Paid claim opened with "This can't be approved until these are
        # fixed" and "worth checking before approving" stacked above "already
        # been paid" — advice about a decision nobody will take again. The
        # index has suppressed these on non-actionable rows for a while.
        expense = expense_at("Paid", receipt: false, budget: nil)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_response :success
        assert_no_match(/can't be approved until these are fixed/i, response.body)
        assert_no_match(/worth checking before approving/i, response.body)
        assert_match(/already been paid/i, response.body)
      end

      test "edit still gives approval advice on an Approved claim" do
        expense = expense_at("Approved", receipt: false, budget: nil)
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/can't be approved until these are fixed/i, response.body)
      end

      # --- Edit renders at every status ------------------------------------

      EDITABLE_STATUSES.each do |status|
        test "edit renders for a #{status} expense" do
          expense = expense_at(status)
          sign_in @user

          get :edit, params: { id: expense.record_id }

          assert_response :success
          assert_includes response.body, status
        end

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
          # A finance edit never changes the status.
          assert_equal status, expense.status
        end
      end

      # The finance forms read money through AmountParser now, like the submitter form
      # and the budget forms, so a pasted "£1,200" is accepted here too. It has to be
      # the PARSED value that gets written: ActiveRecord casts a string to a decimal
      # column with to_d, which reads "£1,200" as 0 — a validated amount would have
      # become a zero payment.
      test "update accepts a currency-formatted amount and stores the parsed number" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "£1,200.50",
                                 amount_excl_vat: "£1,000", description: "x",
                                 payment_reference: "y", budget_record_id: @budget.record_id }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert_equal BigDecimal("1200.50"), expense.amount
        assert_equal BigDecimal("1000"), expense.amount_excl_vat
      end

      test "update reads a comma decimal as a decimal, not a thousands separator" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "12,50", description: "x",
                                 payment_reference: "y", budget_record_id: @budget.record_id }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal BigDecimal("12.50"), expense.reload.amount,
                     "12,50 is twelve pounds fifty, not one thousand two hundred and fifty"
      end

      test "update leaves excl VAT untouched when zero is submitted" do
        expense = expense_at("Paid")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "0",
                                 description: "x", payment_reference: "y",
                                 budget_record_id: @budget.record_id }

        assert_equal BigDecimal("10.42"), expense.reload.amount_excl_vat
      end

      # --- Expense type ----------------------------------------------------

      # The producer form offers Reimbursement and Invoice; finance's own From
      # EUSA is only settable here, and re-typing here is the only way to fix a
      # claim a producer filed wrong.
      test "update re-types a claim, including to finance's own From EUSA" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", payment_reference: "y",
                                 budget_record_id: @budget.record_id,
                                 expense_type: ::Reimbursements::Expense::TYPE_FROM_EUSA }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, expense.reload.expense_type
      end

      test "update rejects an expense type that isn't one of ours" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: @budget.record_id,
                                 expense_type: "Petty cash" }

        assert_response :unprocessable_content
        assert_match(/unknown expense type/i, response.body)
        assert_equal "Reimbursement", expense.reload.expense_type, "nothing was written"
      end

      # Same rule as the producer form: with no overrides, EffectivePayee falls
      # back to the submitter's own bank details, so the Invoice would pay them.
      test "update rejects switching a payable claim to Invoice with no payee overrides" do
        expense = expense_at("Approved")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: @budget.record_id,
                                 expense_type: ::Reimbursements::Expense::TYPE_INVOICE }

        assert_response :unprocessable_content
        assert_match(/would pay Pat Producer/i, response.body)
        assert_equal "Reimbursement", expense.reload.expense_type, "nothing was written"
      end

      test "update accepts Invoice once the payee overrides are filled in" do
        expense = expense_at("Approved")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: @budget.record_id,
                                 expense_type: ::Reimbursements::Expense::TYPE_INVOICE,
                                 payee_name_override: "Acme Ltd", sort_code_override: "20-00-00",
                                 account_number_override: "12345678" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal ::Reimbursements::Expense::TYPE_INVOICE, expense.reload.expense_type
      end

      # Submitted and Paid are records of what EUSA already did, so the payment
      # can't be misdirected any more — and a historical row whose supplier
      # details we never captured has to stay re-typable.
      %w[Submitted Paid].each do |status|
        test "update re-types an already-processed #{status} claim to Invoice without overrides" do
          expense = expense_at(status)
          sign_in @user

          patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                   description: "x", budget_record_id: @budget.record_id,
                                   expense_type: ::Reimbursements::Expense::TYPE_INVOICE }

          assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
          assert_equal ::Reimbursements::Expense::TYPE_INVOICE, expense.reload.expense_type
        end
      end

      # The other forms that post here (Review's inline save, the receipt
      # attach/remove buttons) send no expense_type at all.
      test "update leaves the type alone when the field isn't posted" do
        expense = expense_at("Pending", expense_type: ::Reimbursements::Expense::TYPE_INVOICE,
                                        payee_name_override: "Acme Ltd",
                                        sort_code_override: "20-00-00",
                                        account_number_override: "12345678")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: @budget.record_id,
                                 payee_name_override: "Acme Ltd", sort_code_override: "20-00-00",
                                 account_number_override: "12345678" }

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

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: "999999999" }

        assert_response :unprocessable_content
        assert_match(/budget no longer exists/i, response.body)
        assert_equal "Fake blood", expense.reload.description, "nothing was written"
      end

      test "update rejects a negative amount, re-renders edit 422, writes nothing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "-5", amount_excl_vat: "35.00",
                                 description: "x", budget_record_id: @budget.record_id }

        assert_response :unprocessable_content
        assert_match(/valid amount/i, response.body)
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      test "update rejects a non-numeric amount, re-renders edit 422, writes nothing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "abc", amount_excl_vat: "35.00",
                                 description: "x", budget_record_id: @budget.record_id }

        assert_response :unprocessable_content
        assert_match(/valid amount/i, response.body)
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      # --- The international rail ---------------------------------------------

      def international_expense(status: "Pending", **attrs)
        expense_at(status).tap do |e|
          e.update!(payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
                    foreign_amount: BigDecimal("266.69"),
                    foreign_currency: ::Reimbursements::Expense::CURRENCY_EUR,
                    payee_name_override: "Ausland GmbH",
                    iban_override: "DE89370400440532013000", bic_override: "DEUTDEFF500", **attrs)
        end
      end

      def international_params(expense, **overrides)
        { id: expense.record_id, amount: "230.00", amount_excl_vat: "230.00",
          description: "Festival insurance", budget_record_id: @budget.record_id,
          payee_name_override: "Ausland GmbH",
          iban_override: "DE89 3704 0044 0532 0130 00", bic_override: "deutdeff500",
          foreign_amount: "266.69", foreign_currency: "EUR" }.merge(overrides)
      end

      # The all-or-nothing override rule reads the UK trio, and an international
      # claim has a payee name with no sort code — so saving one refused with a
      # message naming fields the rail does not use.
      test "update saves an international claim instead of demanding a sort code" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense)

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal "Ausland GmbH", expense.reload.payee_name_override
      end

      test "update edits the IBAN and BIC, normalising both" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, iban_override: "NL91 ABNA 0417 1643 00",
                                                             bic_override: " abnanl2a ")

        settled = expense.reload
        assert_equal "NL91ABNA0417164300", settled.iban_override
        assert_equal "ABNANL2A", settled.bic_override
      end

      test "update edits the invoice amount and its currency" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, foreign_amount: "500.00",
                                                             foreign_currency: "USD")

        settled = expense.reload
        assert_equal BigDecimal("500.00"), settled.foreign_amount
        assert_equal "USD", settled.foreign_currency
      end

      # The last point anything checks the number before EUSA's bank acts on it.
      test "update rejects an IBAN that fails its check digits, writes nothing" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, iban_override: "DE88 3704 0044 0532 0130 00")

        assert_response :unprocessable_content
        assert_match(/IBAN/i, response.body)
        assert_equal "DE89370400440532013000", expense.reload.iban_override, "nothing was written"
      end

      test "update rejects a malformed BIC, writes nothing" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, bic_override: "DEUTDEFF5")

        assert_response :unprocessable_content
        assert_match(/BIC/i, response.body)
        assert_equal "DEUTDEFF500", expense.reload.bic_override, "nothing was written"
      end

      test "update rejects an unlisted currency, writes nothing" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, foreign_currency: "XYZ")

        assert_response :unprocessable_content
        assert_equal ::Reimbursements::Expense::CURRENCY_EUR, expense.reload.foreign_currency
      end

      # Same all-or-nothing rule as the UK rail, over the pair this one routes on.
      test "update rejects a half-filled international trio" do
        expense = international_expense
        sign_in @user

        patch :update, params: international_params(expense, bic_override: "")

        assert_response :unprocessable_content
        assert_match(/all three/i, response.body)
      end

      # A Paid claim records what EUSA already did; its supplier details may
      # never have been captured, so it must stay editable without inventing any.
      test "update leaves a Paid international claim editable with blank overrides" do
        expense = international_expense(status: "Paid", payee_name_override: "",
                                        iban_override: "", bic_override: "")
        sign_in @user

        patch :update, params: international_params(expense, payee_name_override: "",
                                                             iban_override: "", bic_override: "")

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
      end

      test "update rejects a malformed sort code override, re-renders edit 422, writes nothing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: @budget.record_id,
                                 sort_code_override: "20-00-0X", account_number_override: "12345678" }

        assert_response :unprocessable_content
        assert_match(/sort code override/i, response.body)
        assert_nil expense.reload.sort_code_override, "nothing was written"
      end

      test "update rejects a malformed account number override, re-renders edit 422, writes nothing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: @budget.record_id,
                                 sort_code_override: "20-00-00", account_number_override: "1234" }

        assert_response :unprocessable_content
        assert_match(/account number override/i, response.body)
        assert_nil expense.reload.account_number_override, "nothing was written"
      end

      test "update allows blank bank-detail overrides (no override, fall back to the payee's own)" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: @budget.record_id,
                                 sort_code_override: "", account_number_override: "" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        expense.reload
        assert_equal "", expense.sort_code_override
        assert_equal "", expense.account_number_override
      end

      test "update rejects a partial bank-detail override (splicing a third party's details)" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: @budget.record_id,
                                 sort_code_override: "20-00-00", account_number_override: "" }

        assert_response :unprocessable_content
        assert_match(/fill in all three/i, response.body)
        assert_nil expense.reload.sort_code_override, "nothing was written"
      end

      test "update rejects an excl-VAT amount greater than the total" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "25.00",
                                 description: "x", budget_record_id: @budget.record_id }

        assert_response :unprocessable_content
        assert_match(/can't be more than the total/i, response.body)
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      # --- Already-sent / already-paid note --------------------------------

      test "shows an already-sent-to-EUSA note for a Submitted expense" do
        expense = expense_at("Submitted")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/already been sent to EUSA/i, response.body)
      end

      test "shows an already-paid note for a Paid expense" do
        expense = expense_at("Paid")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_match(/already been (sent to EUSA|paid)/i, response.body)
      end

      test "shows no such note for a Pending expense" do
        expense = expense_at("Pending")
        sign_in @user

        get :edit, params: { id: expense.record_id }

        assert_no_match(/already been (sent to EUSA|paid)/i, response.body)
      end

      # --- Lookup ----------------------------------------------------------

      test "find without a query shows the lookup form" do
        sign_in @user

        get :find

        assert_response :success
      end

      test "find resolves an auto-number to the edit page" do
        expense = expense_at("Paid", auto_number: 42)
        sign_in @user

        get :find, params: { q: "42" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
      end

      test "find resolves a record id to the edit page" do
        expense = expense_at("Submitted", auto_number: 7)
        sign_in @user

        get :find, params: { q: expense.record_id }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
      end

      test "find with no match flashes and re-renders the lookup" do
        sign_in @user

        get :find, params: { q: "999" }

        assert_response :success
        assert_match(/no expense/i, response.body)
      end

      test "find degrades to no-match, not a 500, for a non-numeric query" do
        sign_in @user

        assert_nothing_raised { get :find, params: { q: "not-an-id" } }

        assert_response :success
        assert_match(/no expense/i, response.body)
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

      # ActiveStorage renders a PDF's first page, so a PDF receipt has a real
      # thumbnail. Asking whether the file is an image (rather than whether it
      # has a preview) drops it to a generic document icon instead.
      test "edit renders a PDF receipt as a real first-page preview image" do
        expense = two_receipt_expense
        sign_in @user

        get :edit, params: { id: expense.record_id }

        first, second = expense.receipts
        assert_match(/<img[^>]+src="#{Regexp.escape(first.preview_url)}"/, response.body)
        assert_match(/<img[^>]+src="#{Regexp.escape(second.preview_url)}"/, response.body)
        assert_match %r{^/admin/reimbursements/expenses/\d+/receipts/\d+/thumbnail$}, first.preview_url
      end

      # Request 2: the receipt opens in the page. The only remaining new-tab link
      # is the explicit "Open in a new tab" fallback inside the viewer pane.
      test "edit opens a PDF receipt in an in-page frame rather than a new tab" do
        expense = two_receipt_expense
        sign_in @user

        get :edit, params: { id: expense.record_id }

        receipt = expense.receipts.first
        assert_match(/<iframe[^>]+data-src="#{Regexp.escape(receipt.url)}"/, response.body)
        assert_match(/<iframe[^>]+title="Receipt: a\.pdf"/, response.body)
        # The thumbnails are buttons, and the only receipt link that still opens a
        # tab is the explicitly labelled fallback inside the pane.
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

      test "remove_receipt drops a receipt and redirects to edit" do
        expense = two_receipt_expense
        removed = expense.receipt_files.find { |file| file.filename.to_s == "a.pdf" }
        sign_in @user

        delete :remove_receipt, params: { id: expense.record_id, attachment_id: removed.blob_id.to_s }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        assert_equal [ "b.pdf" ], expense.reload.receipt_files.map { |file| file.filename.to_s }
      end

      test "add_receipts attaches an uploaded file and redirects to edit" do
        expense = expense_at("Paid")
        sign_in @user

        assert_difference -> { expense.receipt_files.count }, 1 do
          post :add_receipts, params: { id: expense.record_id,
                                        receipts: [ fixture_file_upload("reimbursements_receipt.pdf", "application/pdf") ] }
        end

        assert_redirected_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
      end
      # Both banners were drawn for the same empty fields: "no bank details"
      # from ReviewSupport, and — because the checker returns INVALID for a
      # blank pair — "Modulus check failed ... likely a typo" right under it.
      # The second sent finance hunting for a typo in a field that is empty.
      # This is the state the 140 imported claims were in.
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
      # Finance could not change it at all, so a claim matched to the wrong
      # person — by email-in, or by the settled-claim import, where a blank
      # Submitter email once sent 140 production claims to one payee — could
      # only be fixed from a console.

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

      test "saving a different payee re-points the claim" do
        other = other_payee
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, person_record_id: other.record_id,
                                 amount: "12.50", description: "Fake blood" }

        assert_equal other.id, expense.reload.person_id
      end

      # The case it exists for is a batch of imported claims already Paid to
      # the wrong payee, so the window is deliberately every status — unlike
      # the rail and the type, which stop at Approved.
      test "the payee can be corrected on a Paid claim" do
        other = other_payee
        expense = expense_at("Paid")
        sign_in @user

        patch :update, params: { id: expense.record_id, person_record_id: other.record_id,
                                 amount: "12.50", description: "Fake blood" }

        assert_equal other.id, expense.reload.person_id
      end

      test "a payee id the page never offered is refused rather than 500ing" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, person_record_id: "999999",
                                 amount: "12.50", description: "Fake blood" }

        assert_response :unprocessable_content
        assert_match(/no longer in the registry/, response.body)
        assert_equal @person.id, expense.reload.person_id
      end

      test "a blank payee leaves the claim with the one it has" do
        expense = expense_at("Pending")
        sign_in @user

        patch :update, params: { id: expense.record_id, person_record_id: "",
                                 amount: "12.50", description: "Fake blood" }

        assert_equal @person.id, expense.reload.person_id,
                     "a claim with no payee at all is the state the BACS pre-flight refuses"
      end

      # --- Reopening a rejected claim -----------------------------------------
      # A rejection was terminal: nothing in the portal wrote a status back to
      # Pending.

      test "a rejected claim can be put back in the queue" do
        expense = expense_at("Rejected", rejection_reason: "No receipt attached")
        sign_in @user

        post :reopen, params: { id: expense.record_id }

        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status
      end

      # Never straight to Approved: the claim re-enters finance's queue and the
      # owner gate as a fresh one would, so reopening cannot be a way round a
      # sign-off.
      test "reopening goes to Pending, not Approved" do
        expense = expense_at("Rejected", rejection_reason: "No receipt attached")
        sign_in @user

        post :reopen, params: { id: expense.record_id }

        refute_equal ::Reimbursements::Status::APPROVED, expense.reload.status
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
