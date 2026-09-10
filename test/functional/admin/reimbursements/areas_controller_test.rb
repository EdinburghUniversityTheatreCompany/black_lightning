require "test_helper"

module Admin
  module Reimbursements
    class AreasControllerTest < ActionController::TestCase
      tests Admin::Reimbursements::AreasController
      include ReimbursementsTestHelpers

      setup do
        @user = users(:admin)
        grant_finance_permission(@user)
        sign_in @user
      end

      test "index requires the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "creates an area with its owners" do
        person = create_reimbursements_person(name: "Alice", email: "alice@example.com")

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :create, params: { name: "Cogito", initial_budget: "£1,200",
                                  owner_ids: [ person.record_id ] }
        end

        area = ::Reimbursements::Area.order(:id).last
        assert_equal "Cogito", area.name
        assert_equal 1200, area.initial_budget, "a typed £1,200 must not store as 0"
        assert_equal [ person.record_id ], area.owner_ids
      end

      test "rejects a blank name" do
        assert_no_difference -> { ::Reimbursements::Area.count } do
          post :create, params: { name: "" }
        end

        assert_response :unprocessable_entity
      end

      test "adds a budget line to an area through nested attributes" do
        area = create_reimbursements_area(name: "Cogito")

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320" } }
          }
        end

        assert_equal "Cogito: Marketing", area.reload.budgets.last.name
      end

      test "detaching a budget nils its area rather than deleting it" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { id: budget.id, area_id: "" } }
          }
        end

        assert_nil budget.reload.area
      end

      # --- Nested budget rows -------------------------------------------------
      # DatabaseStore#in_year and #in_cost_centre are deliberately lenient, so a
      # line stamped with neither shows up in EVERY year's and EVERY centre's
      # list — and, being active by default, in every producer's budget picker
      # in both cost centres. That is the exact state BudgetImport#adoptions
      # exists to prevent, and the area's own coordinates are knowable here.
      test "a budget line added through the area inherits its year and cost centre" do
        year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        centre = ::Reimbursements::CostCentre.default
        area = create_reimbursements_area(name: "Cogito", financial_year: year, cost_centre: centre)

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320" } }
        }

        budget = area.reload.budgets.last
        assert_equal year.id, budget.financial_year_id
        assert_equal centre.id, budget.cost_centre_id
      end

      test "a budget line with no nominal code is rejected, not filed under (none)" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: " " } }
          }
        end

        assert_response :unprocessable_entity
      end

      # Budget validates its name, so a blank one reached save! and 500'd the
      # form rather than reporting anything the operator could act on.
      test "a budget line with a blank name is rejected rather than raising" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: " ", nominal_code: "432320" } }
          }
        end

        assert_response :unprocessable_entity
      end

      test "a nested budget row cannot carry fields the form does not render" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320",
                                         initial_budget: "£1,200", active: "0" } }
        }

        budget = area.reload.budgets.last
        # AR casts a raw String to a decimal column with to_d, so a permitted
        # "£1,200" would have stored as 0 — a figure nobody typed.
        assert_nil budget.initial_budget
        assert budget.active
      end
    end
  end
end
