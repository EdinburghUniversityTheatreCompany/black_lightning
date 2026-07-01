require "test_helper"

class Admin::MaintenanceCreditsControllerTest < ActionController::TestCase
  setup do
    @maintenance_credit = maintenance_credits(:one)
    @maintenance_session = maintenance_sessions(:one)

    sign_in users(:admin)

    # You must update these to not directly copy the fixture but put in original data.
    @params = {
      maintenance_credit: { maintenance_session_id: @maintenance_session.id, user_id: @maintenance_credit.user_id }
    }
  end

  test "should get index" do
    get :index

    assert_response :success
    assert_not_nil assigns(:maintenance_credits)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create maintenance_credit" do
    assert_difference("MaintenanceCredit.count") do
      post :create, params: @params
    end

    assert_redirected_to admin_maintenance_credit_url(assigns(:maintenance_credit))
  end

  test "should not create maintenance_credit when invalid" do
    params = { maintenance_credit: { maintenance_session_id: "not an id" } }

    assert_no_difference("MaintenanceCredit.count") do
      post :create, params: params
    end

    assert_response :unprocessable_entity
  end

  test "should show maintenance_credit" do
    get :show, params: { id: @maintenance_credit }
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @maintenance_credit }
    assert_response :success
  end

  test "should update maintenance_credit" do
    patch :update, params: { id: @maintenance_credit, maintenance_credit: { user_id: users(:admin) } }
    assert_redirected_to admin_maintenance_credit_url(@maintenance_credit)
  end

  test "should not update maintenance_credit when invalid" do
    params = { id: @maintenance_credit, maintenance_credit: { maintenance_session_id: "not an id" } }

    patch :update, params: params
    assert_response :unprocessable_entity
  end

  test "should destroy maintenance_credit" do
    assert_difference("MaintenanceCredit.count", -1) do
      delete :destroy, params: { id: @maintenance_credit }
    end

    assert_redirected_to admin_maintenance_credits_url
  end
end
