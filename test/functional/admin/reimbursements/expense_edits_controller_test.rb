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

      # --- Needs-attention reasons tooltip + AI badge ----------------------

      test "index flags a needs-attention expense with a reasons tooltip" do
        rebuild_store(expenses: [ expense_at("Pending", receipts: []) ])
        sign_in @user

        get :index

        assert_includes response.body, "cursor-help"
        assert_includes response.body, "Needs attention: no receipt"
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
