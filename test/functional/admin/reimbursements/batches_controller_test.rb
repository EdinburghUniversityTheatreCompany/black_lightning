require "test_helper"

module Admin
  module Reimbursements
    class BatchesControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

      setup do
        @user = users(:member)
        grant_finance_permission(@user)

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

      # A batch with one linked expense in +status+. It reads as drafted through
      # date_sent unless a draft_message_id is given.
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
        # From the cost centre, so a second one never sends a request labelled Fringe.
        assert_includes response.body, "#{::Reimbursements::CostCentre.default.name} BACS Request",
                        "default EUSA subject is prefilled"
      end

      # Otherwise every account number is on screen the moment the page loads.
      test "new masks bank details, keeping the full pair only behind the reveal" do
        one_approved
        sign_in @user

        get :new

        assert_no_match(/>[^<]*66374958/, response.body,
                        "the account number must not be rendered as visible text")
        assert_includes response.body, "****4958"
        assert_select "[data-bank-details-target='value'][data-revealed=?]", "08-99-99 / 66374958"
        assert_select "button[aria-label='Reveal bank details for Alice Producer']"
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
          post :create, params: { bacs_date: "2026-05-13", eusa_recipient: "", sender_name: "Fringe Finance" }
        end

        assert_redirected_to admin_reimbursements_batches_path
        assert_equal ::Reimbursements::CostCentre.default.eusa_recipient_or_default,
                     enqueued_jobs.last["arguments"].first["eusa_recipient"], "a blank recipient falls back"
        assert_match(/building/i, flash[:notice])
        # Nothing is processed inline.
        assert_equal 0, ::Reimbursements::Batch.count
        assert_equal ::Reimbursements::Status::APPROVED, expense.reload.status
        attempt = ::Reimbursements::BatchAttempt.recent_first.first
        assert attempt.building?
        assert_equal Date.new(2026, 5, 13), attempt.bacs_date
        assert_equal @user.email, attempt.triggered_by_email
      end

      test "index shows an in-flight build and a failed build's errors, dismissing only the failed one" do
        building = ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                                          bacs_date: Date.new(2026, 5, 13))
        failed = ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                                        bacs_date: Date.new(2026, 5, 12), status: "failed",
                                                        error_messages: "EUSA draft creation failed: boom")
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "A batch is building"
        assert_includes response.body, "failed"
        assert_includes response.body, "EUSA draft creation failed: boom"
        assert_select "form[action=?]", dismiss_admin_reimbursements_batch_attempt_path(failed)
        assert_select "form[action=?]", dismiss_admin_reimbursements_batch_attempt_path(building), count: 0
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

      test "create with a blank or malformed BACS date re-renders new and enqueues nothing" do
        one_approved
        sign_in @user

        [ "not-a-date", "" ].each do |value|
          assert_no_enqueued_jobs do
            post :create, params: { bacs_date: value, eusa_recipient: "finance@eusa.ed.ac.uk" }
          end

          assert_response :unprocessable_entity
          assert_match(/valid BACS date/i, response.body)
        end
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

      # --- History (index / show) -------------------------------------------

      test "History lists a batch by its BACS date, with its total, reopen and CSV links" do
        # Nothing records whether the draft was sent: date_sent is the typed date.
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "2026-05-13"
        assert_match(/BACS 20\d\d-\d\d-\d\d/, response.body)
        assert_no_match(/Sent 20\d\d-\d\d-\d\d/, response.body)
        assert_includes response.body, "Reopen for rebuild"
        assert_includes response.body, "£12.50", "the batch's total (its one expense's amount) must render"
        assert_includes response.body, "Download CSV"
        assert_includes response.body, "/admin/reimbursements/batches?format=csv"
      end

      # --- CSV export --------------------------------------------------------

      test "index CSV export is a text/csv download with one row per batch" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "msg-1",
                           sharepoint_backup_url: "https://sp.example/batch")
        # A second expense, so the row summarises rather than repeats.
        create_reimbursements_expense(person: create_reimbursements_person(name: "Sam", email: "sam@example.com"),
                                      batch: @batch, auto_number: 12,
                                      status: ::Reimbursements::Status::PAID,
                                      amount: BigDecimal("20"), amount_excl_vat: BigDecimal("16.67"))
        create_reimbursements_batch(name: "Broken batch", date_sent: nil, draft_message_id: nil)
        sign_in @user

        get :index, format: :csv

        assert_csv_download("batches")
        rows = CSV.parse(response.body)
        assert_equal [ "Date sent", "Name", "Expenses", "Total", "Total ex VAT",
                       "EUSA draft", "SharePoint backup", "Cost centre" ], rows.first
        assert_equal 3, rows.size, "header + one row per batch"

        batch = rows.find { |r| r[0] == "2026-05-13" }
        assert_equal "2", batch[2], "two expenses on the batch"
        assert_equal "32.5", batch[3], "12.50 + 20.00 gross"
        assert_equal "27.09", batch[4], "10.42 + 16.67 ex VAT"
        assert_equal "Yes", batch[5]
        assert_equal "https://sp.example/batch", batch[6]

        broken = rows.find { |r| r[1] == "Broken batch" }
        assert_nil broken[0], "no send date"
        assert_equal "0", broken[2]
        assert_equal "No", broken[5]
      end

      test "index badges a batch whose EUSA draft is missing vs one that succeeded" do
        # Broken: no draft message id AND no date_sent.
        create_reimbursements_batch(name: "Good batch", date_sent: Date.new(2026, 5, 13),
                                    draft_message_id: "AAMkGood==")
        create_reimbursements_batch(name: "Broken batch", date_sent: nil)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Draft created"
        assert_includes response.body, "No EUSA draft: needs a look"
      end

      test "show badges the draft and producer-notification states, warning on a missing one" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==", producer_notifications_sent: false)
        sign_in @user

        get :show, params: { id: @batch.record_id }

        assert_response :success
        # "Not sent": the column records the send attempt, never delivery.
        assert_includes response.body, "Not sent: needs a look"
      end

      test "show and reopen 404 for an unknown batch id" do
        sign_in @user

        get :show, params: { id: "999999" }
        assert_response :not_found

        post :reopen, params: { id: "999999" }
        assert_response :not_found
      end

      # --- Reopen ------------------------------------------------------------

      test "reopen reverts the linked expenses and deletes the batch" do
        # No stored draft id: nothing to confirm, so only the manual warning.
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

        # The revert and the batch delete still happen.
        assert_redirected_to admin_reimbursements_batches_path
        assert_equal ::Reimbursements::Status::APPROVED, @expense.reload.status
        assert_not ::Reimbursements::Batch.exists?(@batch.id)
        assert_match(/delete the old EUSA draft.*manually/i, flash[:alert])
      end

      test "reopen is blocked when the draft can't be confirmed as still unsent" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                           draft_message_id: "AAMkdraft==")
        graph = use_graph
        graph.draft_still_exists = false # sent, deleted, or Graph unreachable
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

      # --- Saying only what is actually known --------------------------------

      test "Detail labels the typed date 'BACS date' and does not claim delivery" do
        batch = batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        batch.update!(producer_notifications_sent: true)
        sign_in @user

        get :show, params: { id: batch.record_id }

        assert_response :success
        assert_includes response.body, "Submitted"
        assert_match(/BACS date/, response.body)
        assert_no_match(/Date sent/, response.body)
        assert_match(/delivery is not tracked/, response.body)
      end

      test "Build Batch's empty state links to the Review queue" do
        sign_in @user

        get :new

        assert_response :success
        assert_select "a[href=?]",
                      admin_reimbursements_review_path(cost_centre: ::Reimbursements::CostCentre.default.key)
      end

      # --- Follow-up failures collapse past a short list ---------------------

      test "History lists a short set of follow-up failures inline" do
        sign_in @user
        messages = Array.new(::Admin::Reimbursements::BatchesController::INLINE_FAILURE_MESSAGES) do |i|
          "receipt #{i} did not reach SharePoint"
        end
        ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                               status: "completed",
                                               error_messages: messages.join("\n"))

        get :index

        assert_response :success
        # The sidebar uses <details> too, so look for this disclosure's summary.
        assert_no_match(/Show all \d+ messages/, response.body, "a short list stays inline")
        assert_match(/receipt 0 did not reach SharePoint/, response.body)
      end

      test "History collapses a wall of follow-up failures behind a count" do
        sign_in @user
        count = ::Admin::Reimbursements::BatchesController::INLINE_FAILURE_MESSAGES + 12
        messages = Array.new(count) { |i| "receipt #{i} did not reach SharePoint" }
        ::Reimbursements::BatchAttempt.create!(cost_centre: ::Reimbursements::CostCentre.default,
                                               status: "completed",
                                               error_messages: messages.join("\n"))

        get :index

        assert_response :success
        assert_match(/#{count} follow-up steps failed/, response.body)
        assert_select "details summary", text: "Show all #{count} messages"
        assert_match(/receipt #{count - 1} did not reach SharePoint/, response.body)
      end

      test "a dismissed failure is gone from History" do
        sign_in @user
        attempt = ::Reimbursements::BatchAttempt.create!(
          cost_centre: ::Reimbursements::CostCentre.default,
          status: "failed", error_messages: "a distinctive failure message"
        )
        attempt.dismiss!

        get :index

        assert_response :success
        assert_no_match(/a distinctive failure message/, response.body)
      end

      # --- The EUSA draft link ----------------------------------------------

      test "History and Detail link the EUSA draft" do
        batch = batch_with_expense(status: ::Reimbursements::Status::SUBMITTED,
                                   draft_message_id: "msg-1",
                                   draft_web_link: "https://outlook.example/draft-1")
        sign_in @user

        get :index
        assert_select "a[href=?]", "https://outlook.example/draft-1"

        get :show, params: { id: batch.record_id }
        assert_select "a[href=?]", "https://outlook.example/draft-1"
      end

      test "a batch built before the link was stored says so rather than rendering nothing" do
        batch_with_expense(status: ::Reimbursements::Status::SUBMITTED, draft_message_id: "msg-1")
        sign_in @user

        get :index

        assert_response :success
        assert_match(/Draft link not recorded/, response.body)
      end

      # --- Checking whether it is still unsent -------------------------------

      test "reports a draft that is still unsent" do
        graph = use_graph
        graph.draft_still_exists = true
        batch = batch_with_expense(status: ::Reimbursements::Status::SUBMITTED, draft_message_id: "msg-1")
        sign_in @user

        post :check_draft, params: { id: batch.record_id }

        assert_match(/still UNSENT/, flash[:notice])
      end

      # Fails CLOSED, so the message must not claim the draft was sent.
      test "refuses to say a draft is sent when it only failed to confirm it" do
        graph = use_graph
        graph.draft_still_exists = false
        batch = batch_with_expense(status: ::Reimbursements::Status::SUBMITTED, draft_message_id: "msg-1")
        sign_in @user

        post :check_draft, params: { id: batch.record_id }

        assert_match(/Couldn't confirm/, flash[:alert])
        assert_no_match(/has been sent/, flash[:alert])
        assert ::Reimbursements::Batch.exists?(batch.id), "the probe must not delete the batch"
        assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
        assert_empty graph.deleted_messages
      end

      test "a batch with no recorded draft has nothing to check" do
        batch = batch_with_expense(status: ::Reimbursements::Status::SUBMITTED)
        sign_in @user

        post :check_draft, params: { id: batch.record_id }

        assert_match(/nothing to check/, flash[:alert])
      end
    end
  end
end
