require "test_helper"

module Admin
  module Reimbursements
    class HelpControllerTest < ActionController::TestCase
      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
      end

      test "requires sign-in" do
        get :show
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :show
        assert_response :forbidden
      end

      test "a finance manager sees the setup guide" do
        sign_in users(:member)
        get :show
        assert_response :success
        assert_includes response.body, "Adding a new reimbursement mailbox"
        assert_includes response.body, "Sites.Selected"
      end
    end
  end
end
