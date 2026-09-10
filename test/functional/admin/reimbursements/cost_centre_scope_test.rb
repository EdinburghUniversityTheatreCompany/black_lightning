require "test_helper"

module Admin
  module Reimbursements
    ##
    # The ?cost_centre= selector across every finance screen it scopes.
    #
    # One file rather than a block in each controller's own test, because the
    # thing under test is a TWO-cost-centre world and building one is not free:
    # the fixture set deliberately holds exactly ONE cost centre (a second
    # fixture makes CostCentre.default resolve to whichever label
    # FixtureSet.identify hashes lower, and deletes the one-centre world the
    # reconcile tests pin as a business rule), so the second centre is built
    # here with create_reimbursements_cost_centre.
    #
    # Separate top-level classes rather than nested ones: ActionController
    # ::TestCase carries `tests SomeController` down to subclasses along with
    # every inherited test, so a nested class would silently re-run its
    # parent's cases against the wrong controller.
    module CostCentreScopeSetup
      extend ActiveSupport::Concern
      include ReimbursementsTestHelpers

      included do
        setup do
          finance = Role.create!(name: "Business Manager")
          finance.permissions << Permission.create(action: "manage",
                                                   subject_class: "reimbursements_finance")
          users(:member).add_role("Business Manager")
          @user = users(:member)
          sign_in @user

          @fringe = ::Reimbursements::CostCentre.default
          @termtime = create_reimbursements_cost_centre(
            key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
            receive_mailbox: "in@bedlamtheatre.invalid", send_mailbox: "out@bedlamtheatre.invalid"
          )

          @payee = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                                sort_code: "203045", account_number: "44444444")
          @fringe_budget = create_reimbursements_budget(name: "Fringe props", nominal_code: "4000",
                                                        cost_centre: @fringe, initial_budget: 1000)
          @termtime_budget = create_reimbursements_budget(name: "Termtime props", nominal_code: "4000",
                                                          cost_centre: @termtime, initial_budget: 500)
          @unplaced_budget = create_reimbursements_budget(name: "Unplaced props", nominal_code: "4000")
        end
      end
    end

    class BudgetsCostCentreScopeTest < ActionController::TestCase
      include CostCentreScopeSetup

      tests BudgetsController

      test "the budgets index lists every cost centre when none is selected" do
        get :index

        assert_response :success
        assert_equal [ "Fringe props", "Termtime props", "Unplaced props" ],
                     assigns(:budgets).map(&:name).sort
      end

      test "?cost_centre= narrows the budgets index to that centre, keeping unplaced lines" do
        get :index, params: { cost_centre: "termtime" }

        assert_response :success
        assert_equal [ "Termtime props", "Unplaced props" ], assigns(:budgets).map(&:name).sort
      end

      test "?cost_centre_id= is still honoured, for the links that shipped with it" do
        get :index, params: { cost_centre_id: @termtime.id }

        assert_response :success
        assert_equal [ "Termtime props", "Unplaced props" ], assigns(:budgets).map(&:name).sort
      end

      test "an unknown cost-centre key says so and falls back to every centre" do
        get :index, params: { cost_centre: "nope" }

        assert_response :success
        assert_match(/no cost centre called .*nope/, response.body)
        assert_equal 3, assigns(:budgets).size
      end

      test "the overview subtotals one cost centre rather than adding the two together" do
        get :overview, params: { cost_centre: "fringe" }

        assert_response :success
        rollup = assigns(:rollups).find { |r| r.code == "4000" }
        # 1000 (Fringe) + 0 (unplaced) — NOT 1500, which is what folding
        # termtime's line into the same nominal code used to print.
        assert_equal BigDecimal("1000"), rollup.initial
      end

      test "the overview's unattributed-actuals card is scoped too" do
        ::Reimbursements::EusaActual.create!(narrative: "Fringe stray", debit: 10,
                                             nominal_code: "4000", cost_centre: @fringe)
        ::Reimbursements::EusaActual.create!(narrative: "Termtime stray", debit: 20,
                                             nominal_code: "4000", cost_centre: @termtime)

        get :overview, params: { cost_centre: "fringe" }

        narratives = assigns(:unattributed_by_code).values.flatten.map(&:narrative)
        assert_includes narratives, "Fringe stray"
        assert_not_includes narratives, "Termtime stray"
      end

      test "a new budget lands in the cost centre whose budgets are on screen" do
        post :create, params: { cost_centre: "termtime", name: "New line",
                                nominal_code: "4100", budget_type: "Expense" }

        assert_equal @termtime.id, ::Reimbursements::Budget.find_by(name: "New line").cost_centre_id
      end
    end

    class ReviewCostCentreScopeTest < ActionController::TestCase
      include CostCentreScopeSetup

      tests ReviewController

      setup do
        create_reimbursements_expense(person: @payee, budget: @fringe_budget,
                                      description: "Fringe claim")
        create_reimbursements_expense(person: @payee, budget: @termtime_budget,
                                      description: "Termtime claim")
        create_reimbursements_expense(person: @payee, budget: @unplaced_budget,
                                      description: "Unplaced claim")
      end

      test "the review queue and its tab counts both narrow to the selected centre" do
        get :index, params: { cost_centre: "fringe" }

        assert_response :success
        assert_equal [ "Fringe claim", "Unplaced claim" ], assigns(:pending).map(&:description).sort
        # Every tab comes off the same list, so a count can never disagree with
        # the rows under it.
        assert_equal assigns(:pending).size,
                     assigns(:awaiting_owner).size + assigns(:to_approve).size
      end

      test "the review CSV follows the selected centre as well as the tab" do
        get :index, params: { cost_centre: "termtime", format: :csv }

        assert_response :success
        assert_includes response.body, "Termtime claim"
        assert_not_includes response.body, "Fringe claim"
      end
    end

    class ActualsCostCentreScopeTest < ActionController::TestCase
      include CostCentreScopeSetup

      tests ActualsController

      setup do
        ::Reimbursements::EusaActual.create!(narrative: "Fringe row", debit: 10,
                                             cost_centre: @fringe, period: "P1")
        ::Reimbursements::EusaActual.create!(narrative: "Termtime row", debit: 20,
                                             cost_centre: @termtime, period: "P1")
      end

      test "the actuals ledger narrows to the selected centre" do
        get :index, params: { cost_centre: "fringe" }

        assert_response :success
        narratives = assigns(:actuals).map(&:narrative)
        assert_includes narratives, "Fringe row"
        assert_not_includes narratives, "Termtime row"
      end

      test "the actuals CSV narrows too" do
        get :index, params: { cost_centre: "fringe", format: :csv }

        assert_response :success
        assert_includes response.body, "Fringe row"
        assert_not_includes response.body, "Termtime row"
      end
    end

    class BatchesCostCentreScopeTest < ActionController::TestCase
      include CostCentreScopeSetup

      tests BatchesController

      setup do
        fringe_batch = ::Reimbursements::Batch.create!(name: "Fringe run", date_sent: Date.current)
        termtime_batch = ::Reimbursements::Batch.create!(name: "Termtime run", date_sent: Date.current)
        create_reimbursements_expense(person: @payee, budget: @fringe_budget, batch: fringe_batch,
                                      status: ::Reimbursements::Status::SUBMITTED)
        create_reimbursements_expense(person: @payee, budget: @termtime_budget, batch: termtime_batch,
                                      status: ::Reimbursements::Status::SUBMITTED)
      end

      test "batch history takes each batch's centre from the expenses it holds" do
        get :index, params: { cost_centre: "fringe" }

        assert_response :success
        names = assigns(:batches).map(&:name)
        assert_includes names, "Fringe run"
        assert_not_includes names, "Termtime run"
      end

      test "the batches CSV narrows too" do
        get :index, params: { cost_centre: "termtime", format: :csv }

        assert_response :success
        assert_includes response.body, "Termtime run"
        assert_not_includes response.body, "Fringe run"
      end
    end
  end
end
