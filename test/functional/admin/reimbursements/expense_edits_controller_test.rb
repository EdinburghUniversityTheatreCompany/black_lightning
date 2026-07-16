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

      EXP = FIELD_IDS[:expenses]
      EDITABLE_STATUSES = %w[Pending Approved Submitted Paid].freeze
      MC = ::Reimbursements::ModulusCheck

      # Modulus verdict keyed by account number, so tests don't depend on the
      # gitignored Pay.UK rule files.
      class FakeChecker
        def initialize(by_account = {})
          @by_account = by_account
        end

        def check(_sort_code, account_number)
          @by_account.fetch(account_number, MC::OUTSIDE_SPEC)
        end
      end

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = airtable_person_record(id: "recPer1", name: "Pat Producer", email: "pat@example.com",
                                         sort_code: "08-99-99", account_number: "66374958")
        @budget = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000")

        @checker = FakeChecker.new("66374958" => MC::VALID)
        ExpenseEditsController.checker_builder = -> { @checker }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
        ExpenseEditsController.checker_builder = -> { MC.default_checker }
      end

      def expense_at(status, id: "recExp1", **attrs)
        airtable_expense_record(id: id, status: status, **attrs)
      end

      def two_receipts
        [
          { "id" => "att1", "filename" => "a.pdf", "url" => "https://airtable/a", "size" => 10, "type" => "application/pdf" },
          { "id" => "att2", "filename" => "b.pdf", "url" => "https://airtable/b", "size" => 20, "type" => "application/pdf" }
        ]
      end

      def image_receipt
        { "id" => "attImg", "filename" => "receipt.jpg", "url" => "https://airtable/img.jpg",
          "size" => 100, "type" => "image/jpeg",
          "thumbnails" => { "large" => { "url" => "https://airtable/thumb.jpg" } } }
      end

      def rebuild_store(expenses:)
        @store, @client = build_fake_store(expenses: expenses, people: [ @person ], budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
      end

      # --- Auth gating -----------------------------------------------------

      test "requires sign-in" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        get :edit, params: { id: "recExp1" }
        assert_redirected_to new_user_session_path
      end

      test "the producer portal permission alone does not grant finance access" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in other

        get :edit, params: { id: "recExp1" }

        assert_response :forbidden
      end

      # --- Index: all-expenses table with filters + search ----------------

      # A store with two budgets and two payees across three statuses, so the
      # filter/search tests can prove narrowing (and exclusion).
      def rebuild_multi_store
        person2 = airtable_person_record(id: "recPer2", name: "Sam Stagehand", email: "sam@example.com",
                                         sort_code: "20-00-00", account_number: "12345678")
        budget2 = airtable_budget_record(id: "recBud2", name: "Costumes", nominal_code: "4100")
        expenses = [
          expense_at("Pending",  id: "recExp1", auto_number: 1, description: "Fake blood",
                                  payment_reference: "PROPS PAT", budget_id: "recBud1", payee_id: "recPer1"),
          expense_at("Approved", id: "recExp2", auto_number: 2, description: "Velvet cloak",
                                  payment_reference: "COSTUMES SAM", budget_id: "recBud2",
                                  payee_id: "recPer2", amount: 99.0),
          expense_at("Paid",     id: "recExp3", auto_number: 3, description: "Stage nails",
                                  payment_reference: "PROPS PAT", budget_id: "recBud1",
                                  payee_id: "recPer1", amount: 5.0)
        ]
        @store, @client = build_fake_store(expenses: expenses, people: [ @person, person2 ],
                                           budgets: [ @budget, budget2 ])
        BaseController.store_builder = -> { @store }
      end

      test "index requires the finance permission (producer access alone is forbidden)" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in other

        get :index

        assert_response :forbidden
      end

      test "index lists every expense with a link to edit each" do
        rebuild_multi_store
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Fake blood"
        assert_includes response.body, "Velvet cloak"
        assert_includes response.body, "Stage nails"
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path("recExp1")
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path("recExp2")
        assert_includes response.body, edit_admin_reimbursements_expense_edit_path("recExp3")
      end

      test "index status filter narrows to a single status" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { status: "Paid" }

        assert_response :success
        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Velvet cloak"
      end

      test "index budget filter narrows to a single budget" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { budget: "recBud2" }

        assert_response :success
        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Stage nails"
      end

      test "index search matches a description substring and excludes non-matches" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { q: "velvet" }

        assert_response :success
        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Stage nails"
      end

      test "index search matches the effective payee name" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { q: "stagehand" }

        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search matches an exact auto-number" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { q: "3" }

        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search matches a numeric amount, stripping a £ prefix and commas" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { q: "£99.00" }

        assert_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
      end

      test "index search with a non-numeric, non-matching query returns no rows without raising" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { q: "not a number and no substring match" }

        assert_response :success
        assert_not_includes response.body, "Velvet cloak"
        assert_not_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
      end

      # --- CSV export --------------------------------------------------------

      test "index CSV export answers a text/csv download named for today" do
        rebuild_multi_store
        sign_in @user

        get :index, format: :csv

        assert_response :success
        assert_includes response.media_type, "text/csv"
        assert_match(/attachment/, response.headers["Content-Disposition"])
        assert_match(/reimbursements-expenses-\d{4}-\d{2}-\d{2}\.csv/, response.headers["Content-Disposition"])
      end

      test "index CSV export has a header row and one data row per expense" do
        rebuild_multi_store
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                       "Description", "Payment reference", "Submitted", "Needs attention" ], rows.first
        assert_equal 4, rows.size, "header + three expenses"
        # A concrete data row: the Paid "Stage nails" expense to Pat, £5.00, Props.
        stage = rows.find { |r| r[6] == "Stage nails" }
        assert_equal %w[3 Paid], stage.values_at(0, 1)
        assert_equal "Pat Producer", stage[2]
        assert_equal "Props", stage[3]
        assert_equal "5.0", stage[4]
      end

      test "index CSV export carries the on-screen filter, exporting only the filtered set" do
        rebuild_multi_store
        sign_in @user

        get :index, params: { status: "Paid" }, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 2, rows.size, "header + the single Paid expense"
        assert_includes response.body, "Stage nails"
        assert_not_includes response.body, "Fake blood"
        assert_not_includes response.body, "Velvet cloak"
      end

      test "index CSV export lists the full filtered set, not just the first page" do
        rebuild_paged_store(60)
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 61, rows.size, "header + all 60 expenses (pagination is display-only)"
      end

      test "index CSV export joins the needs-attention reasons" do
        # An expense with no ex-VAT amount and no budget flags two reasons.
        flagged = expense_at("Pending", id: "recExpFlag", auto_number: 7, description: "Flagged item",
                             amount_excl_vat: nil, budget_id: nil)
        @store, @client = build_fake_store(expenses: [ flagged ], people: [ @person ], budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        reasons = rows.find { |r| r[6] == "Flagged item" }.last
        assert_includes reasons, "no ex-VAT amount"
        assert_includes reasons, "no budget"
      end

      # --- Pagination (50 per page, filters carry across pages) ------------

      # Build `count` Pending expenses, newest first by submitted_at so the
      # ordering (and therefore which slice lands on which page) is deterministic.
      def rebuild_paged_store(count)
        expenses = (1..count).map do |n|
          expense_at("Pending", id: "recExp#{n}", auto_number: n,
                     description: "Expense number #{n}",
                     overrides: { EXP[:submitted_at] => "2026-05-#{format('%02d', (n % 28) + 1)}T00:00:00.000Z" })
        end
        @store, @client = build_fake_store(expenses: expenses, people: [ @person ], budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
      end

      test "index pages the list at 50 per page" do
        rebuild_paged_store(60)
        sign_in @user

        get :index
        page1_rows = response.body.scan(/Expense number \d+/).uniq.size
        assert_equal 50, page1_rows, "first page should show 50 of 60 expenses"
        assert_includes response.body, "60 expenses"
      end

      test "index page 2 returns the next slice, not page 1's rows" do
        rebuild_paged_store(60)
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
        pending = (1..60).map do |n|
          expense_at("Pending", id: "recP#{n}", auto_number: n, description: "Pending row #{n}",
                     overrides: { EXP[:submitted_at] => "2026-05-#{format('%02d', (n % 28) + 1)}T00:00:00.000Z" })
        end
        paid = (1..20).map do |n|
          expense_at("Paid", id: "recQ#{n}", auto_number: 100 + n, description: "Paid row #{n}")
        end
        @store, @client = build_fake_store(expenses: pending + paid, people: [ @person ], budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
        sign_in @user

        get :index, params: { status: "Pending", page: 2 }

        assert_response :success
        assert_includes response.body, "60 expenses"
        assert_equal 10, response.body.scan(/Pending row \d+/).uniq.size, "page 2 should show the last 10 Pending rows"
        assert_equal 0, response.body.scan(/Paid row \d+/).size, "a Paid expense must never appear under the Pending filter"
        # The Pending filter must survive onto the pager links.
        assert_match(/[?&]status=Pending/, response.body)
      end

      # --- Needs-attention reasons tooltip + AI badge ----------------------

      test "index flags a needs-attention expense with an accessible reasons popover" do
        rebuild_store(expenses: [ expense_at("Pending", receipts: []) ])
        sign_in @user

        get :index

        # A focusable <button> trigger wired to the popover controller, carrying
        # the aria attributes a title= tooltip never had, and the reasons render.
        assert_select "[data-controller='popover']" do
          assert_select "button[aria-expanded='false'][aria-controls='reasons-edits-recExp1']",
                        text: /Needs attention/
          assert_select "#reasons-edits-recExp1 li", text: "no receipt"
        end
      end

      test "index does not flag a clean expense" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        get :index

        # The filter checkbox says "Needs attention only"; the row tooltip (with a
        # colon + reasons) is what must be absent for a clean expense.
        assert_not_includes response.body, "Needs attention:"
      end

      test "index shows a colour-coded AI badge for a checked expense" do
        rebuild_store(expenses: [ expense_at("Pending", overrides: { EXP[:ai_check_status] => "pass" }) ])
        sign_in @user

        get :index

        assert_includes response.body, "AI: Pass"
        assert_includes response.body, "text-success"
      end

      test "edit lists the reasons an expense needs attention" do
        rebuild_store(expenses: [ expense_at("Pending", receipts: []) ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_match(/needs attention before it's ready to pay/i, response.body)
        assert_includes response.body, "no receipt"
      end

      test "edit shows no attention list for a clean expense" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_no_match(/needs attention before it's ready to pay/i, response.body)
      end

      # --- Edit renders at every status ------------------------------------

      EDITABLE_STATUSES.each do |status|
        test "edit renders for a #{status} expense" do
          rebuild_store(expenses: [ expense_at(status) ])
          sign_in @user

          get :edit, params: { id: "recExp1" }

          assert_response :success
          assert_includes response.body, status
        end

        test "update persists edits for a #{status} expense via update_expense!" do
          rebuild_store(expenses: [ expense_at(status) ])
          sign_in @user

          patch :update, params: { id: "recExp1", amount: "42.00", amount_excl_vat: "35.00",
                                   description: "Edited #{status}", payment_reference: "REF-#{status}",
                                   nominal_code_override: "4100", budget_record_id: "recBud1",
                                   payee_name_override: "Acme Ltd", sort_code_override: "20-00-00",
                                   account_number_override: "12345678" }

          assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
          _table, record_id, fields = @client.updated.sole
          assert_equal "recExp1", record_id
          assert_equal 42.0, fields[EXP[:amount]]
          assert_equal 35.0, fields[EXP[:amount_excl_vat]]
          assert_equal "Edited #{status}", fields[EXP[:description]]
          assert_equal "REF-#{status}", fields[EXP[:payment_reference]]
          assert_equal "4100", fields[EXP[:nominal_code_override]]
          assert_equal "Acme Ltd", fields[EXP[:payee_name_override]]
          assert_equal "20-00-00", fields[EXP[:sort_code_override]]
          assert_equal "12345678", fields[EXP[:account_number_override]]
          # A finance edit never changes the status.
          assert_not fields.key?(EXP[:status])
        end
      end

      test "update leaves excl VAT untouched when zero is submitted" do
        rebuild_store(expenses: [ expense_at("Paid") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "0",
                                 description: "x", payment_reference: "y", budget_record_id: "recBud1" }

        _table, _id, fields = @client.updated.sole
        assert_not fields.key?(EXP[:amount_excl_vat])
      end

      test "update rejects a budget_record_id that doesn't resolve to a real budget" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "16.67",
                                 description: "x", budget_record_id: "recBudGone" }

        assert_response :unprocessable_content
        assert_match(/budget no longer exists/i, response.body)
        assert_empty @client.updated
      end

      test "update rejects a negative amount, re-renders edit 422, writes nothing" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "-5", amount_excl_vat: "35.00",
                                 description: "x", budget_record_id: "recBud1" }

        assert_response :unprocessable_content
        assert_match(/valid amount/i, response.body)
        assert_empty @client.updated
      end

      test "update rejects a non-numeric amount, re-renders edit 422, writes nothing" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "abc", amount_excl_vat: "35.00",
                                 description: "x", budget_record_id: "recBud1" }

        assert_response :unprocessable_content
        assert_match(/valid amount/i, response.body)
        assert_empty @client.updated
      end

      test "update rejects a malformed sort code override, re-renders edit 422, writes nothing" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: "recBud1",
                                 sort_code_override: "20-00-0X", account_number_override: "12345678" }

        assert_response :unprocessable_content
        assert_match(/sort code override/i, response.body)
        assert_empty @client.updated
      end

      test "update rejects a malformed account number override, re-renders edit 422, writes nothing" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: "recBud1",
                                 sort_code_override: "20-00-00", account_number_override: "1234" }

        assert_response :unprocessable_content
        assert_match(/account number override/i, response.body)
        assert_empty @client.updated
      end

      test "update allows blank bank-detail overrides (no override, fall back to the payee's own)" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: "recBud1",
                                 sort_code_override: "", account_number_override: "" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
        _table, _id, fields = @client.updated.sole
        assert_equal "", fields[EXP[:sort_code_override]]
        assert_equal "", fields[EXP[:account_number_override]]
      end

      test "update rejects a partial bank-detail override (splicing a third party's details)" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "20.00",
                                 description: "x", budget_record_id: "recBud1",
                                 sort_code_override: "20-00-00", account_number_override: "" }

        assert_response :unprocessable_content
        assert_match(/fill in all three/i, response.body)
        assert_empty @client.updated
      end

      test "update rejects an excl-VAT amount greater than the total" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        patch :update, params: { id: "recExp1", amount: "20.00", amount_excl_vat: "25.00",
                                 description: "x", budget_record_id: "recBud1" }

        assert_response :unprocessable_content
        assert_match(/can't be more than the total/i, response.body)
        assert_empty @client.updated
      end

      # --- Already-sent / already-paid note --------------------------------

      test "shows an already-sent-to-EUSA note for a Submitted expense" do
        rebuild_store(expenses: [ expense_at("Submitted") ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_match(/already been sent to EUSA/i, response.body)
      end

      test "shows an already-paid note for a Paid expense" do
        rebuild_store(expenses: [ expense_at("Paid") ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_match(/already been (sent to EUSA|paid)/i, response.body)
      end

      test "shows no such note for a Pending expense" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_no_match(/already been (sent to EUSA|paid)/i, response.body)
      end

      # --- Lookup ----------------------------------------------------------

      test "find without a query shows the lookup form" do
        rebuild_store(expenses: [ expense_at("Pending") ])
        sign_in @user

        get :find

        assert_response :success
      end

      test "find resolves an auto-number to the edit page" do
        rebuild_store(expenses: [ expense_at("Paid", id: "recExp1", auto_number: 42) ])
        sign_in @user

        get :find, params: { q: "42" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
      end

      test "find resolves a record id to the edit page" do
        rebuild_store(expenses: [ expense_at("Submitted", id: "recExp1", auto_number: 7) ])
        sign_in @user

        get :find, params: { q: "recExp1" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
      end

      test "find resolves a record id via a live fetch even when the cached list is stale" do
        rebuild_store(expenses: [])
        sign_in @user
        # A record created by another process (e.g. the mailbox poll job)
        # after this store's expenses list was already cached — lookup_expense
        # must fall back to a live single-record fetch, not just the cache.
        @store.expenses
        @client.list_records(:expenses) << expense_at("Submitted", id: "recExpNew", auto_number: 99)

        get :find, params: { q: "recExpNew" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExpNew")
      end

      test "find with no match flashes and re-renders the lookup" do
        rebuild_store(expenses: [])
        sign_in @user

        get :find, params: { q: "999" }

        assert_response :success
        assert_match(/no expense/i, response.body)
      end

      test "editing an unknown expense 404s" do
        rebuild_store(expenses: [])
        sign_in @user

        get :edit, params: { id: "recNope" }

        assert_response :not_found
      end

      # --- Receipts --------------------------------------------------------

      test "edit renders an image receipt as a fancybox thumbnail keyed to the expense" do
        rebuild_store(expenses: [ expense_at("Approved", receipts: [ image_receipt ]) ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_includes response.body, 'data-controller="fancybox"'
        assert_includes response.body, 'data-fancybox="receipts-recExp1"'
        # The lightbox link opens the full image; the thumbnail previews it.
        assert_includes response.body, "https://airtable/img.jpg"
        assert_includes response.body, "https://airtable/thumb.jpg"
      end

      test "edit renders a PDF receipt as a new-tab link, not a broken image" do
        rebuild_store(expenses: [ expense_at("Approved", receipts: two_receipts) ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_includes response.body, 'target="_blank"'
        assert_includes response.body, "fa-file-lines"
        # A PDF must never be wired to fancybox as an inline image.
        assert_no_match(/<img[^>]+https:\/\/airtable\/a/, response.body)
      end

      test "edit keeps the finance Remove button and Attach form" do
        rebuild_store(expenses: [ expense_at("Approved", receipts: two_receipts) ])
        sign_in @user

        get :edit, params: { id: "recExp1" }

        assert_includes response.body, ">Remove</button>"
        assert_includes response.body,
                        admin_reimbursements_expense_edit_receipts_path("recExp1")
      end

      test "remove_receipt drops a receipt and redirects to edit" do
        rebuild_store(expenses: [ expense_at("Approved", receipts: two_receipts) ])
        sign_in @user

        delete :remove_receipt, params: { id: "recExp1", attachment_id: "att1" }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
        _table, record_id, _fields = @client.updated.sole
        assert_equal "recExp1", record_id
      end

      test "add_receipts attaches an uploaded file and redirects to edit" do
        rebuild_store(expenses: [ expense_at("Paid") ])
        sign_in @user

        post :add_receipts, params: { id: "recExp1",
                                      receipts: [ fixture_file_upload("reimbursements_receipt.pdf", "application/pdf") ] }

        assert_redirected_to edit_admin_reimbursements_expense_edit_path("recExp1")
        assert_equal 1, @client.uploads.size
      end
    end
  end
end
