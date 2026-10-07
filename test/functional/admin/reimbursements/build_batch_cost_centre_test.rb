require "test_helper"

module Admin
  module Reimbursements
    ##
    # Build Batch is one cost centre's operation. The second centre is built here,
    # never as a fixture (CostCentre.default would resolve by FixtureSet hash).
    class BuildBatchCostCentreTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

      tests BatchesController

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        sign_in @user

        @termtime = create_second_reimbursements_cost_centre

        payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com",
                                             sort_code: "08-99-99", account_number: "66374958")
        create_reimbursements_expense(
          person: payee, auto_number: 11, status: ::Reimbursements::Status::APPROVED,
          budget: create_reimbursements_budget(name: "Fringe props", cost_centre: ::Reimbursements::CostCentre.default)
        )
        create_reimbursements_expense(
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

      # Asks rather than bounces: with no centre selected the sidebar link carries none.
      test "with several centres and none chosen, it asks which rather than picking one" do
        get :new

        assert_response :success
        assert_template :choose_cost_centre
        assert_nil assigns(:cost_centre)
        assert_nil assigns(:expenses), "nothing is previewed before a pot is chosen"
      end

      test "the build is enqueued for the chosen centre, and its attempt row records it" do
        assert_enqueued_with(job: ::Reimbursements::BuildBatchJob) do
          post :create, params: { cost_centre: "termtime", bacs_date: Date.current.iso8601 }
        end

        assert_equal @termtime.id, ::Reimbursements::BatchAttempt.sole.cost_centre_id
        assert_equal "termtime", enqueued_jobs.last["arguments"].first["cost_centre_key"]
      end
    end
  end
end
