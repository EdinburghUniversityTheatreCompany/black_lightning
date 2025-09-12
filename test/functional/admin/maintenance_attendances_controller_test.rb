require "test_helper"

class Admin::MaintenanceAttendancesControllerTest < ActionController::TestCase
  # TODO: all of this
  setup do
    @maintenance_attendance = maintenance_attendances(:one)
    @maintenance_session = maintenance_sessions(:one)

    sign_in users(:admin)

    # You must update these to not directly copy the fixture but put in original data.
    @params = {
      maintenance_attendance: { maintenance_session_id: @maintenance_session.id, user_id: @maintenance_attendance.user_id }
    }
  end

  test "should get index" do
    get :index

    assert_response :success
    assert_not_nil assigns(:maintenance_attendances)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create maintenance_attendance" do
    assert_difference("MaintenanceAttendance.count") do
      post :create, params: @params
    end

    assert_redirected_to admin_maintenance_attendance_url(assigns(:maintenance_attendance))
  end

  test "should not create maintenance_attendance when invalid" do
    params = { maintenance_attendance: { maintenance_session_id: "not an id" } }

    assert_no_difference("MaintenanceAttendance.count") do
      post :create, params: params
    end

    assert_response :unprocessable_entity
  end

  test "should show maintenance_attendance" do
    get :show, params: { id: @maintenance_attendance }
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @maintenance_attendance }
    assert_response :success
  end

  test "should update maintenance_attendance" do
    patch :update, params: { id: @maintenance_attendance, maintenance_attendance: { user_id: users(:admin) } }
    assert_redirected_to admin_maintenance_attendance_url(@maintenance_attendance)
  end

  test "should not update maintenance_attendance when invalid" do
    params = { id: @maintenance_attendance, maintenance_attendance: { maintenance_session_id: "not an id" } }

    patch :update, params: params
    assert_response :unprocessable_entity
  end

  test "should destroy maintenance_attendance" do
    assert_difference("MaintenanceAttendance.count", -1) do
      delete :destroy, params: { id: @maintenance_attendance }
    end

    assert_redirected_to admin_maintenance_attendances_url
  end
end
