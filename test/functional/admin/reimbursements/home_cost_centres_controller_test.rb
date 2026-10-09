require "test_helper"

module Admin
  module Reimbursements
    class HomeCostCentresControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @termtime = create_second_reimbursements_cost_centre
        sign_in @user
        request.env["HTTP_REFERER"] = "http://test.host/admin/reimbursements/review?cost_centre=termtime"
      end

      test "makes the selected centre the user's default and goes back to the page" do
        patch :update, params: { cost_centre: "termtime" }

        assert_equal @termtime, @user.reload.reimbursements_cost_centre
        assert_redirected_to "http://test.host/admin/reimbursements/review?cost_centre=termtime"
      end

      test "clears the default" do
        @user.update!(reimbursements_cost_centre: @termtime)

        delete :destroy

        assert_nil @user.reload.reimbursements_cost_centre
        assert_redirected_to "http://test.host/admin/reimbursements/review?cost_centre=termtime"
      end

      test "refuses to set a default with no centre named" do
        patch :update

        assert_nil @user.reload.reimbursements_cost_centre
        assert_match(/choose a cost centre/i, flash[:alert])
      end

      test "never redirects off-site" do
        request.env["HTTP_REFERER"] = "https://evil.example/phish"

        patch :update, params: { cost_centre: "termtime" }

        assert_redirected_to admin_reimbursements_root_path
      end

      test "needs the finance permission" do
        sign_in users(:committee)

        patch :update, params: { cost_centre: "termtime" }

        assert_response :forbidden
      end
    end
  end
end
