require "test_helper"

module Admin
  module Reimbursements
    class NominalCodesControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      NC = ::Reimbursements::NominalCode

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @cost_centre = ::Reimbursements::CostCentre.default
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :index, params: { key: @cost_centre.key }
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :index, params: { key: @cost_centre.key }
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant access" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        sign_in other

        get :index, params: { key: @cost_centre.key }

        assert_response :forbidden
      end

      # --- Index -------------------------------------------------------------

      test "index lists this cost centre's codes and not another centre's" do
        termtime = create_second_reimbursements_cost_centre
        create_reimbursements_nominal_code(code: "432320", label: "Marketing", cost_centre: @cost_centre)
        create_reimbursements_nominal_code(code: "555555", label: "Termtime printing", cost_centre: termtime)
        sign_in @user

        get :index, params: { key: @cost_centre.key }

        assert_response :success
        assert_equal [ "432320" ], assigns(:nominal_codes).map(&:code)
        assert_includes response.body, "Marketing"
        assert_not_includes response.body, "Termtime printing"
      end

      test "index 404s for a cost centre that does not exist" do
        sign_in @user

        get :index, params: { key: "no-such-centre" }

        assert_response :not_found
      end

      # --- Create ------------------------------------------------------------

      test "create adds a code to this cost centre" do
        sign_in @user

        assert_difference -> { NC.count }, +1 do
          post :create, params: { key: @cost_centre.key, code: "432320", label: "Marketing" }
        end

        code = NC.order(:id).last
        assert_equal "432320", code.code
        assert_equal "Marketing", code.label
        assert_equal @cost_centre.id, code.cost_centre_id
        assert code.active?
        assert_redirected_to admin_reimbursements_nominal_codes_path(@cost_centre.key)
      end

      test "create refuses a blank code and re-renders the list" do
        sign_in @user

        assert_no_difference -> { NC.count } do
          post :create, params: { key: @cost_centre.key, code: "", label: "Marketing" }
        end

        assert_response :unprocessable_entity
        assert_includes response.body, "Code must not be blank"
      end

      test "create refuses a code the centre already lists, whatever its case" do
        create_reimbursements_nominal_code(code: "abc123", cost_centre: @cost_centre)
        sign_in @user

        assert_no_difference -> { NC.count } do
          post :create, params: { key: @cost_centre.key, code: "ABC123", label: "Shouted" }
        end

        assert_response :unprocessable_entity
      end

      test "the same code may be listed by two cost centres" do
        termtime = create_second_reimbursements_cost_centre
        create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        sign_in @user

        assert_difference -> { NC.count }, +1 do
          post :create, params: { key: termtime.key, code: "432320", label: "Termtime marketing" }
        end
      end

      # --- Update ------------------------------------------------------------

      test "update corrects the seeded label guess" do
        code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                  cost_centre: @cost_centre)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, label: "Marketing & publicity" }

        assert_equal "Marketing & publicity", code.reload.label
        assert_redirected_to admin_reimbursements_nominal_codes_path(@cost_centre.key)
      end

      test "update cannot rewrite the code itself" do
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, code: "999999", label: "Renamed" }

        assert_equal "432320", code.reload.code
        assert_equal "Renamed", code.label
      end

      test "update refuses a blank label" do
        code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                  cost_centre: @cost_centre)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, label: "" }

        assert_response :unprocessable_entity
        assert_equal "Marketing", code.reload.label
      end

      test "update puts a retired code back in the picker" do
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre,
                                                  active: false)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, active: "1" }

        assert code.reload.active?
      end

      test "update 404s for a code belonging to another cost centre" do
        termtime = create_second_reimbursements_cost_centre
        code = create_reimbursements_nominal_code(code: "555555", cost_centre: termtime)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, label: "Stolen" }

        assert_response :not_found
        assert_not_equal "Stolen", code.reload.label
      end

      # --- Destroy: retiring beats deleting ---------------------------------

      test "a code in use is retired, not deleted" do
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                     cost_centre: @cost_centre)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert NC.exists?(code.id), "a code a budget carries must stay readable"
        assert_not code.reload.active?
      end

      test "a code nothing references is deleted outright" do
        code = create_reimbursements_nominal_code(code: "999999", cost_centre: @cost_centre)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert_not NC.exists?(code.id)
      end

      # A budget with no cost centre of its own is lenient-scoped into EVERY
      # centre's screens, so this centre's list is what labels its code there.
      test "a code an unplaced budget carries is retired, not deleted" do
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: nil)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert NC.exists?(code.id)
        assert_not code.reload.active?
      end

      test "another centre's budget does not block deleting this centre's code" do
        termtime = create_second_reimbursements_cost_centre
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Termtime marketing", nominal_code: "432320",
                                     cost_centre: termtime)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert_not NC.exists?(code.id)
      end

      test "destroy 404s for a code belonging to another cost centre" do
        termtime = create_second_reimbursements_cost_centre
        code = create_reimbursements_nominal_code(code: "555555", cost_centre: termtime)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert_response :not_found
        assert NC.exists?(code.id)
      end
    end
  end
end
