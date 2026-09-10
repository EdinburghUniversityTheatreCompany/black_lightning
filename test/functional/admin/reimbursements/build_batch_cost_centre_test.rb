require "test_helper"

module Admin
  module Reimbursements
    ##
    # Build Batch is a single-cost-centre operation: one pot's claims, one BACS
    # spreadsheet, one EUSA draft sent from that pot's mailbox. Before this it
    # hardcoded CostCentre.default (order(:id).first) and swept EVERY approved
    # claim in the portal, so with two centres configured termtime's claims went
    # into a Fringe batch.
    #
    # The second cost centre is built here rather than added to the fixtures:
    # a second fixture row makes CostCentre.default resolve to whichever label
    # FixtureSet.identify hashes lower and deletes the one-centre world the
    # reconcile tests pin as a business rule.
    class BuildBatchCostCentreTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

      tests BatchesController

      setup do
        @user = grant_reimbursements_finance(users(:member))
        sign_in @user

        @fringe = ::Reimbursements::CostCentre.default
        @termtime = create_second_reimbursements_cost_centre

        payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com",
                                             sort_code: "08-99-99", account_number: "66374958")
        @fringe_claim = create_reimbursements_expense(
          person: payee, auto_number: 11, status: ::Reimbursements::Status::APPROVED,
          budget: create_reimbursements_budget(name: "Fringe props", cost_centre: @fringe)
        )
        @termtime_claim = create_reimbursements_expense(
          person: payee, auto_number: 12, status: ::Reimbursements::Status::APPROVED,
          budget: create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        )
      end

      test "the build form previews only the selected centre's approved claims" do
        get :new, params: { cost_centre: "termtime" }

        assert_response :success
        assert_equal [ 12 ], assigns(:expenses).map(&:auto_number)
        assert_equal @termtime, assigns(:cost_centre)
      end

      test "with several centres and none chosen, it refuses rather than picking one" do
        get :new

        assert_redirected_to admin_reimbursements_batches_path
        assert_match(/choose which cost centre/i, flash[:alert])
      end

      test "with one centre configured there is nothing to choose" do
        @termtime_claim.destroy!
        @termtime_claim.budget.destroy!
        @termtime.destroy!

        get :new

        assert_response :success
        assert_equal @fringe, assigns(:cost_centre)
      end

      test "the build is enqueued for the chosen centre, and its attempt row records it" do
        assert_enqueued_with(job: ::Reimbursements::BuildBatchJob) do
          post :create, params: { cost_centre: "termtime", bacs_date: Date.current.iso8601 }
        end

        assert_equal @termtime.id, ::Reimbursements::BatchAttempt.sole.cost_centre_id
        assert_equal "termtime", enqueued_jobs.last["arguments"].first["cost_centre_key"]
      end

      # The controller's preview is only a preview: BuildBatchJob re-selects the
      # Approved set at run time (that re-selection is what makes a serialised
      # double-click a clean no-op), so the narrowing has to be there too.
      class RecordingProcessor
        attr_reader :expenses

        def process(expenses:, **)
          @expenses = expenses
          ::Reimbursements::BatchProcessor::Result.new(success: true, errors: [])
        end
      end

      test "the job builds only its own centre's claims" do
        processor = RecordingProcessor.new
        processor_seam = ::Reimbursements::BuildBatchJob.processor_builder
        graph_seam = ::Reimbursements::BuildBatchJob.graph_builder
        ::Reimbursements::BuildBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { processor }
        ::Reimbursements::BuildBatchJob.graph_builder = -> { Object.new }

        ::Reimbursements::BuildBatchJob.perform_now(
          cost_centre_key: "termtime", bacs_date: Date.current.iso8601,
          sender_name: "Finance", eusa_recipient: "eusa@example.invalid", operator_emails: []
        )

        assert_equal [ 12 ], processor.expenses.map(&:auto_number)
      ensure
        ::Reimbursements::BuildBatchJob.processor_builder = processor_seam
        ::Reimbursements::BuildBatchJob.graph_builder = graph_seam
      end
    end
  end
end
