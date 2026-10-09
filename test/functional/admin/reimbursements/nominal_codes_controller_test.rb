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

      def settings_path
        edit_admin_reimbursements_setting_path(@cost_centre.key, anchor: "nominal_codes")
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        post :create, params: { key: @cost_centre.key, code: "432320", label: "Marketing" }
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        post :create, params: { key: @cost_centre.key, code: "432320", label: "Marketing" }
        assert_response :forbidden
      end

      test "404s for a cost centre that does not exist" do
        sign_in @user

        post :create, params: { key: "no-such-centre", code: "432320", label: "Marketing" }

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
        assert_redirected_to settings_path
      end

      test "create refuses a blank code" do
        sign_in @user

        assert_no_difference -> { NC.count } do
          post :create, params: { key: @cost_centre.key, code: "", label: "Marketing" }
        end

        assert_redirected_to settings_path
        assert_match(/Code must not be blank/, flash[:alert])
      end

      # Turbo re-renders the section in place, keeping what was typed.
      test "a refused add re-renders the section with what was typed" do
        sign_in @user

        post :create, params: { key: @cost_centre.key, code: "", label: "Marketing" },
                      format: :turbo_stream

        assert_response :unprocessable_entity
        assert_includes response.body, "nominal_codes"
        assert_includes response.body, "Marketing"
        assert_includes response.body, "Code must not be blank"
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

      test "update corrects a label" do
        code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                  cost_centre: @cost_centre)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, label: "Marketing & publicity" }

        assert_equal "Marketing & publicity", code.reload.label
        assert_redirected_to settings_path
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

        assert flash[:alert].present?
        assert_equal "Marketing", code.reload.label
      end

      test "a refused row edit leaves the add form empty" do
        code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                  cost_centre: @cost_centre)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, id: code.id, label: "" },
                       format: :turbo_stream

        assert_response :unprocessable_entity
        assert_select "input#code[value]", false, "the add form must not prefill from a refused row"
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

      # Rows carry their nominal code as a string, so this list is the only thing
      # that labels it. An unplaced budget is lenient-scoped into every centre.
      test "a code any historical row carries is retired, not deleted" do
        sign_in @user

        {
          "budget" => create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                                   cost_centre: @cost_centre),
          "EUSA actual" => create_reimbursements_actual(nominal_code: "432321",
                                                        cost_centre: @cost_centre),
          "unplaced budget" => create_reimbursements_budget(name: "Unplaced marketing",
                                                            nominal_code: "432322", cost_centre: nil)
        }.each do |kind, row|
          code = create_reimbursements_nominal_code(code: row.nominal_code, cost_centre: @cost_centre)

          delete :destroy, params: { key: @cost_centre.key, id: code.id }

          assert NC.exists?(code.id), "a code a #{kind} carries must stay readable"
          assert_not code.reload.active?, kind
        end
      end

      test "a code nothing references is deleted outright" do
        code = create_reimbursements_nominal_code(code: "999999", cost_centre: @cost_centre)
        sign_in @user

        delete :destroy, params: { key: @cost_centre.key, id: code.id }

        assert_not NC.exists?(code.id)
      end

      test "another centre's rows do not block deleting this centre's code" do
        termtime = create_second_reimbursements_cost_centre
        code = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Termtime marketing", nominal_code: "432320",
                                     cost_centre: termtime)
        create_reimbursements_actual(nominal_code: "432320", cost_centre: termtime)
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
