require "test_helper"

class Admin::MaintenanceSessionsControllerTest < ActionController::TestCase
  setup do
    @admin_maintenance_session = maintenance_sessions(:one)
    @user = users(:member)
    sign_in users(:admin)

    # You must update these to not directly copy the fixture but put in original data.
    @params = {
      maintenance_session: {
        date: @admin_maintenance_session.date,
        maintenance_attendances_attributes: { "0" => { id: "", user_id: @user.id, _destroy: "false" } }
      }
    }
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:maintenance_sessions)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create maintenance_session" do
    assert_difference("MaintenanceSession.count") do
      post :create, params: @params
    end

    assert assigns(:maintenance_session).users.include?(@user), "User is not added to the session"

    assert_redirected_to admin_maintenance_session_url(assigns(:maintenance_session))
  end

  test "should not create maintenance_session when invalid" do
    invalid_params = { maintenance_session: { date: nil } }

    assert_no_difference("MaintenanceSession.count") do
      post :create, params: invalid_params
    end

    assert_response :unprocessable_entity
  end

  test "should show maintenance_session" do
    get :show, params: { id: @admin_maintenance_session }
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @admin_maintenance_session }
    assert_response :success
  end

  test "should update maintenance_session" do
    patch :update, params: { id: @admin_maintenance_session, maintenance_session: { date: "2022-02-02" } }
    assert_redirected_to admin_maintenance_session_url(@admin_maintenance_session)
  end

  test "should not update maintenance_session when invalid" do
    patch :update, params: { id: @admin_maintenance_session, maintenance_session: { date: nil } }
    assert_response :unprocessable_entity
  end

  test "should destroy maintenance_session" do
    maintenance_session_without_attendances = maintenance_sessions(:no_attendances)

    assert_difference("MaintenanceSession.count", -1) do
      delete :destroy, params: { id: maintenance_session_without_attendances }
    end

    assert_redirected_to admin_maintenance_sessions_url
  end
end
