require "test_helper"

module Admin
  module Reimbursements
    class BatchesControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      BATCH_FIDS = FIELD_IDS[:batches]
      EXP_FIDS = FIELD_IDS[:expenses]

      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)

        # Build Batch needs the default cost centre's SharePoint folders configured.
        ::Reimbursements::CostCentre.default.update!(
          sharepoint_receipts_drive_id: "drvR", sharepoint_receipts_folder_id: "fldR",
          sharepoint_bacs_drive_id: "drvB", sharepoint_bacs_folder_id: "fldB"
        )

        @graph = FakeGraphClient.new
        BatchesController.graph_builder = -> { @graph }
      end

      teardown do
        Admin::Reimbursements::BaseController.store_builder = -> { ::Reimbursements::Store.new }
        BatchesController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      def use_store(expenses: [], people: [], budgets: [], batches: [])
        @store, @client = build_fake_store(expenses: expenses, people: people, budgets: budgets,
                                           batches: batches)
        Admin::Reimbursements::BaseController.store_builder = -> { @store }
      end

      def one_approved
        people = [ airtable_person_record(id: "recAlice", name: "Alice Producer", email: "alice@example.com",
                                          sort_code: "08-99-99", account_number: "66374958") ]
        budgets = [ airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000") ]
        expenses = [ airtable_expense_record(id: "recExpA", payee_id: "recAlice", status: "Approved",
                                             auto_number: 11) ]
        use_store(expenses: expenses, people: people, budgets: budgets)
      end

      def linked_expense(status:)
        airtable_expense_record(id: "recExpA", payee_id: "recAlice", status: status, auto_number: 11,
                                overrides: { EXP_FIDS[:batch] => [ "recBat1" ] })
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        use_store
        get :new
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        use_store
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      # --- Build Batch (new) -------------------------------------------------

      test "new previews approved expenses and a prefilled EUSA email" do
        one_approved
        sign_in @user

        get :new

        assert_response :success
        assert_includes response.body, "Alice Producer"
        assert_includes response.body, "Create draft and process batch"
        assert_includes response.body, "Bedlam Fringe BACS Request", "default EUSA subject is prefilled"
      end

      # --- Build Batch (create) ---------------------------------------------

      test "create processes the batch, submits expenses and shows the draft link" do
        one_approved
        sign_in @user

        post :create, params: { bacs_date: "2026-05-13", eusa_recipient: "finance@eusa.ed.ac.uk",
                                sender_name: "Fringe Finance" }

        assert_response :success
        assert_includes response.body, "https://outlook.example/draft-1"
        assert_equal 1, @graph.drafts.size
        assert_equal 1, @client.created.count { |table, _| table == :batches }
        submitted = @client.updated.count { |_, _, fields| fields[EXP_FIDS[:status]] == "Submitted" }
        assert_equal 1, submitted
      end

      # --- History (index / show) -------------------------------------------

      test "index lists past batches with their totals" do
        use_store(batches: [ airtable_batch_record ], expenses: [ linked_expense(status: "Submitted") ],
                  people: [], budgets: [])
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "BACS 2026-05-13"
        assert_includes response.body, "Reopen for rebuild"
      end

      test "show renders one batch and its linked expenses" do
        use_store(batches: [ airtable_batch_record ], expenses: [ linked_expense(status: "Submitted") ])
        sign_in @user

        get :show, params: { id: "recBat1" }

        assert_response :success
        assert_includes response.body, "Submitted"
      end

      # --- Reopen ------------------------------------------------------------

      test "reopen reverts the linked expenses and deletes the batch" do
        use_store(batches: [ airtable_batch_record ], expenses: [ linked_expense(status: "Submitted") ])
        sign_in @user

        post :reopen, params: { id: "recBat1" }

        assert_redirected_to admin_reimbursements_batches_path
        assert(@client.updated.any? { |_, _, fields| fields[EXP_FIDS[:status]] == "Approved" })
        assert_equal [ [ :batches, "recBat1" ] ], @client.deleted
      end

      test "reopen is blocked when any linked expense is already Paid" do
        use_store(batches: [ airtable_batch_record ], expenses: [ linked_expense(status: "Paid") ])
        sign_in @user

        post :reopen, params: { id: "recBat1" }

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/already Paid/, flash[:alert])
        assert_empty @client.deleted
      end
    end
  end
end
