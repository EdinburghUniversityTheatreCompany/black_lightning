require "test_helper"

class Admin::DebtsControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
    @member = FactoryBot.create(:member)
  end

  test "should get index" do
    get :index
    assert_response :success

    assert_equal User.with_role(:member).all.ids.sort, assigns(:users).ids.sort, "Not all users with the members role are included in the index"
  end

  test "should get index with only in debt" do
    FactoryBot.create(:overdue_staffing_debt, user: @member)

    get :index, params: { show_in_debt_only: 1 }
    assert_response :success

    assert_includes assigns(:users).to_a, @member, "The user with debt is not included in the index when show_in_debt_only is true"
    assert_not_includes assigns(:users).to_a, @admin, "The user without debt is included in the index when show_in_debt_only is true"
  end

  test "should get show" do
    get :show, params: { id: @member.id }
    assert_response :success
  end

  test "should not get show for other user" do
    sign_out @admin
    sign_in @member

    get :show, params: { id: @admin.id }

    assert_response 403
  end
end
