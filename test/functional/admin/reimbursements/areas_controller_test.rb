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
    end
  end
end
