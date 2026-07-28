require "test_helper"

module Admin
  module Reimbursements
    class FinancialYearsControllerTest < ActionController::TestCase
      FY = ::Reimbursements::FinancialYear

      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)
        @current = FY.create!(label: "Fringe 2026", active: true,
                              starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2027, 7, 31))
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      # --- Index -------------------------------------------------------------

      test "index lists every year, newest first" do
        FY.create!(label: "Fringe 2025", starts_on: Date.new(2025, 8, 1))
        sign_in @user

        get :index

        assert_response :success
        assert_equal [ "Fringe 2026", "Fringe 2025" ], assigns(:financial_years).map(&:label)
        assert_includes response.body, "Fringe 2025"
      end

      # --- Create ------------------------------------------------------------

      test "create makes a DRAFT year and leaves the live year active" do
        sign_in @user

        assert_difference -> { FY.count }, 1 do
          post :create, params: { financial_year: { label: "Fringe 2027",
                                                    starts_on: "2027-08-01", ends_on: "2028-07-31" } }
        end

        created = FY.find_by(label: "Fringe 2027")
        assert_redirected_to edit_admin_reimbursements_financial_year_path(created.key)
        assert_not_predicate created, :active?
        assert_equal "fringe-2027", created.key
        assert_equal Date.new(2027, 8, 1), created.starts_on
        # The whole point of a draft: the portal keeps filing against 2026 until
        # someone deliberately switches over.
        assert_equal @current, FY.current
      end

      test "create re-renders with the operator's input when the label is blank" do
        sign_in @user

        assert_no_difference -> { FY.count } do
          post :create, params: { financial_year: { label: "", starts_on: "2027-08-01" } }
        end

        assert_response :unprocessable_entity
        assert_equal "2027-08-01", assigns(:financial_year).starts_on.to_s
      end

      test "create rejects a duplicate label" do
        sign_in @user

        assert_no_difference -> { FY.count } do
          post :create, params: { financial_year: { label: "Fringe 2026" } }
        end

        assert_response :unprocessable_entity
      end

      # --- Update ------------------------------------------------------------

      test "update saves the label and dates" do
        sign_in @user

        patch :update, params: { key: @current.key,
                                 financial_year: { label: "Fringe 2026 (Aug)", ends_on: "2027-06-30" } }

        assert_redirected_to edit_admin_reimbursements_financial_year_path(@current.key)
        @current.reload
        assert_equal "Fringe 2026 (Aug)", @current.label
        assert_equal Date.new(2027, 6, 30), @current.ends_on
      end

      test "update cannot flip the active flag" do
        draft = FY.create!(label: "Fringe 2027")
        sign_in @user

        patch :update, params: { key: draft.key, financial_year: { label: "Fringe 2027", active: "1" } }

        # Switching the live year is its own confirmed action; a stray param on
        # the edit form must never move the money.
        assert_not_predicate draft.reload, :active?
        assert_equal @current, FY.current
      end

      test "update leaves the key alone once the year exists" do
        sign_in @user

        patch :update, params: { key: @current.key, financial_year: { label: "Renamed", key: "something-else" } }

        assert_equal "fringe-2026", @current.reload.key
      end

      # --- Activate ----------------------------------------------------------

      test "activate switches the live year" do
        draft = FY.create!(label: "Fringe 2027")
        sign_in @user

        post :activate, params: { key: draft.key }

        assert_redirected_to admin_reimbursements_financial_years_path
        assert_predicate draft.reload, :active?
        assert_not_predicate @current.reload, :active?
        assert_equal draft, FY.current
      end

      test "activate on the live year is harmless" do
        sign_in @user

        post :activate, params: { key: @current.key }

        assert_predicate @current.reload, :active?
        assert_equal 1, FY.active.count
      end

      test "activate 404s on an unknown year" do
        sign_in @user

        post :activate, params: { key: "no-such-year" }

        assert_response :not_found
      end
    end
  end
end
