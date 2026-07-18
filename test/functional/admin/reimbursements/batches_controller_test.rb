require "test_helper"

module Admin
  module Reimbursements
    class BatchesControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

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
      end

      teardown do
        Admin::Reimbursements::BatchesController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      def use_graph
        @graph = FakeGraphClient.new
        Admin::Reimbursements::BatchesController.graph_builder = -> { @graph }
        @graph
      end

      def one_approved
        alice = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com",
                                             sort_code: "08-99-99", account_number: "66374958")
        budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")
        create_reimbursements_expense(person: alice, budget: budget, auto_number: 11,
                                      status: ::Reimbursements::Status::APPROVED)
      end

      # A batch whose one linked expense is in +status+ — mirrors the old
      # linked_expense fake. The batch derives eusa_draft_created from
      # date_sent (legacy-sent semantics) unless draft_message_id is given.
      def batch_with_expense(status:, **batch_attrs)
        @batch = create_reimbursements_batch(**batch_attrs)
        @expense = create_reimbursements_expense(person: create_reimbursements_person,
                                                 batch: @batch, auto_number: 11, status: status)
        @batch
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :new
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
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

      test "new redirects with an alert when no cost centre is configured" do
        ::Reimbursements::CostCentre.destroy_all
        sign_in @user

        get :new

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/No cost centre configured/, flash[:alert])
      end

      # --- Build Batch (create) ---------------------------------------------

      test "create enqueues a background build (serialised per cost centre) and redirects to History" do
        expense = one_approved
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::BuildBatchJob) do
          post :create, params: { bacs_date: "2026-05-13", eusa_recipient: "finance@eusa.ed.ac.uk",
                                  sender_name: "Fringe Finance" }
        end

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/building/i, flash[:notice])
        # Nothing is processed inline in the request: no batch, no submit.
        assert_equal 0, ::Reimbursements::Batch.count
        assert_equal ::Reimbursements::Status::APPROVED, expense.reload.status
        # History's in-app trace exists from the moment of the click.
        attempt = ::Reimbursements::BatchAttempt.recent_first.first
        assert attempt.building?
        assert_equal Date.new(2026, 5, 13), attempt.bacs_date
        assert_equal @user.email, attempt.triggered_by_email
      end

      test "index shows an in-flight build and a failed build's errors" do
        ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                               bacs_date: Date.new(2026, 5, 13))
        ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                               bacs_date: Date.new(2026, 5, 12), status: "failed",
                                               error_messages: "EUSA draft creation failed: boom")
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "A batch is building"
        assert_includes response.body, "failed"
        assert_includes response.body, "EUSA draft creation failed: boom"
      end

      test "index flags a stale build that never reported back" do
        stale = ::Reimbursements::BatchAttempt.create!(
          cost_centre: ::Reimbursements::CostCentre.default, bacs_date: Date.new(2026, 5, 13)
        )
        stale.update_column(:created_at, 2.hours.ago)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "hasn't finished"
      end

      test "create with a malformed BACS date re-renders new with an error and enqueues nothing" do
        one_approved
        sign_in @user

        assert_no_enqueued_jobs do
          post :create, params: { bacs_date: "not-a-date", eusa_recipient: "finance@eusa.ed.ac.uk" }
        end

        assert_response :unprocessable_entity
        assert_match(/valid BACS date/i, response.body)
      end

      test "create with a blank BACS date re-renders new with an error and enqueues nothing" do
        one_approved
        sign_in @user

        assert_no_enqueued_jobs do
          post :create, params: { bacs_date: "", eusa_recipient: "finance@eusa.ed.ac.uk" }
        end

        assert_response :unprocessable_entity
        assert_match(/valid BACS date/i, response.body)
      end

      test "create with a malformed EUSA recipient re-renders new with an error and enqueues nothing" do
        one_approved
        sign_in @user

        assert_no_enqueued_jobs do
          post :create, params: { bacs_date: "2026-05-13", eusa_recipient: "not-an-email" }
        end

        assert_response :unprocessable_entity
        assert_match(/valid EUSA recipient/i, response.body)
      end

      test "create with a blank EUSA recipient falls back to the cost centre's default" do
        one_approved
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::BuildBatchJob) do
          post :create, params: { bacs_date: "2026-05-13", eusa_recipient: "" }
        end

        assert_redirected_to admin_reimbursements_batches_path
      end

      # --- History (index / show) -------------------------------------------

      test "index lists past batches with their totals" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "2026-05-13"
        assert_includes response.body, "Reopen for rebuild"
        assert_includes response.body, "£12.50", "the batch's total (its one expense's amount) must render"
      end

      test "index badges a batch whose EUSA draft is missing vs one that succeeded" do
        # Drafted: a stored draft message id. Broken: no id AND no date_sent —
        # the derived predicate reads that as "no EUSA draft".
        create_reimbursements_batch(name: "Good batch", date_sent: Date.new(2026, 5, 13),
                                    draft_message_id: "AAMkGood==")
        create_reimbursements_batch(name: "Broken batch", date_sent: nil)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Draft created"
        assert_includes response.body, "No EUSA draft — needs a look"
      end

      test "show renders one batch and its linked expenses" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        sign_in @user

        get :show, params: { id: @batch.record_id }

        assert_response :success
        assert_includes response.body, "Submitted"
      end

      test "show badges the draft and producer-notification states, warning on a missing one" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==", producer_notifications_sent: false)
        sign_in @user

        get :show, params: { id: @batch.record_id }

        assert_response :success
        # EUSA draft succeeded (green "Yes"), producers were NOT notified (amber warning).
        assert_includes response.body, "No — needs a look"
      end

      test "show 404s for an unknown batch id" do
        sign_in @user

        get :show, params: { id: "999999" }

        assert_response :not_found
      end

      # --- Reopen ------------------------------------------------------------

      test "reopen 404s for an unknown batch id" do
        sign_in @user

        post :reopen, params: { id: "999999" }

        assert_response :not_found
      end

      test "reopen reverts the linked expenses and deletes the batch" do
        # No stored draft id — nothing to confirm either way, so reopen
        # proceeds and falls back to the manual-deletion warning.
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        sign_in @user

        post :reopen, params: { id: @batch.record_id }

        assert_redirected_to admin_reimbursements_batches_path
        assert_equal ::Reimbursements::Status::APPROVED, @expense.reload.status
        assert_nil @expense.batch
        assert_not ::Reimbursements::Batch.exists?(@batch.id)
        assert_match(/delete the old EUSA draft.*manually/i, flash[:alert])
      end

      test "reopen deletes the stale EUSA draft via Graph using the send mailbox and stored id" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==")
        graph = use_graph
        sign_in @user

        post :reopen, params: { id: @batch.record_id }

        assert_redirected_to admin_reimbursements_batches_path
        deleted = graph.deleted_messages.sole
        assert_equal "AAMkdraft==", deleted[:message_id]
        assert_equal ::Reimbursements::CostCentre.default.send_mailbox, deleted[:mailbox]
        assert_match(/draft.*deleted/i, flash[:notice])
      end

      test "reopen still succeeds when deleting the stale draft fails" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==")
        graph = use_graph
        graph.fail_delete_message = true
        sign_in @user

        post :reopen, params: { id: @batch.record_id }

        # The revert + batch delete still happen; only a fallback warning is added.
        assert_redirected_to admin_reimbursements_batches_path
        assert_equal ::Reimbursements::Status::APPROVED, @expense.reload.status
        assert_not ::Reimbursements::Batch.exists?(@batch.id)
        assert_match(/delete the old EUSA draft.*manually/i, flash[:alert])
      end

      test "reopen is blocked when the draft can't be confirmed as still unsent" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==")
        graph = use_graph
        graph.draft_still_exists = false # already sent, deleted, or Graph couldn't be reached
        sign_in @user

        post :reopen, params: { id: @batch.record_id }

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/could not be confirmed as.*still unsent/i, flash[:alert])
        assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status,
                     "must not revert expenses when the draft may already be sent"
        assert ::Reimbursements::Batch.exists?(@batch.id), "must not delete the batch record either"
        assert_empty graph.deleted_messages, "must never attempt to delete an unconfirmed draft"
      end

      test "reopen is blocked when any linked expense is already Paid" do
        batch_with_expense(status: ::Reimbursements::Status::PAID)
        sign_in @user

        post :reopen, params: { id: @batch.record_id }

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/already Paid/, flash[:alert])
        assert ::Reimbursements::Batch.exists?(@batch.id)
      end
    end
  end
end
