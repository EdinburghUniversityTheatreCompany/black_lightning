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

    assert_includes assigns(:maintenance_session).users, @user, "User is not added to the session"

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

  test "should grant multiple credits to one person from a single row" do
    params = {
      maintenance_session: {
        date: Date.current,
        maintenance_attendances_attributes: { "0" => { user_id: @user.id, quantity: "3" } }
      }
    }

    assert_difference("MaintenanceAttendance.count", 3) do
      post :create, params: params
    end

    assert_equal 3, assigns(:maintenance_session).maintenance_attendances.count
  end

  test "should show credit counts on the session page" do
    session = MaintenanceSession.create!(date: Date.current)
    2.times { session.maintenance_attendances.create!(user: @user) }

    get :show, params: { id: session }

    assert_response :success
    assert_equal({ @user.id => 2 }, assigns(:credit_counts))
    # The attendee appears once (deduped), not once per credit.
    assert_equal 1, assigns(:users).to_a.count { |u| u.id == @user.id }
  end

  test "should create maintenance_session with a name" do
    post :create, params: { maintenance_session: { date: Date.current, name: "Spring clean" } }

    session = assigns(:maintenance_session)
    assert_equal "Spring clean", session.name
    assert_equal "Spring clean", session.to_label
  end

  test "to_label falls back to the date when created without a name" do
    post :create, params: { maintenance_session: { date: "2024-03-04" } }

    session = assigns(:maintenance_session)
    assert_nil session.name
    assert_equal session.date, session.to_label
  end

  test "should reconcile credits up and down when editing" do
    session = MaintenanceSession.create!(date: Date.current)
    3.times { session.maintenance_attendances.create!(user: @user) }

    credit_count = -> { MaintenanceAttendance.where(user: @user, maintenance_session: session).count }
    assert_equal 3, credit_count.call

    # Increase 3 -> 5 (builds 2)
    patch :update, params: { id: session, maintenance_session: {
      date: session.date,
      maintenance_attendances_attributes: { "0" => { user_id: @user.id, quantity: "5" } }
    } }
    assert_equal 5, credit_count.call

    # Decrease 5 -> 1 (destroys 4)
    patch :update, params: { id: session, maintenance_session: {
      date: session.date,
      maintenance_attendances_attributes: { "0" => { user_id: @user.id, quantity: "1" } }
    } }
    assert_equal 1, credit_count.call

    # Remove the row entirely (destroys all)
    patch :update, params: { id: session, maintenance_session: {
      date: session.date,
      maintenance_attendances_attributes: { "0" => { user_id: @user.id, _destroy: "1" } }
    } }
    assert_equal 0, credit_count.call
  end

  test "reassigning a row to another user moves the credits" do
    other = users(:committee)
    session = MaintenanceSession.create!(date: Date.current)
    2.times { session.maintenance_attendances.create!(user: @user) }

    # The single rendered row now points at a different user.
    patch :update, params: { id: session, maintenance_session: {
      date: session.date,
      maintenance_attendances_attributes: { "0" => { user_id: other.id, quantity: "2" } }
    } }

    assert_equal 0, MaintenanceAttendance.where(user: @user, maintenance_session: session).count
    assert_equal 2, MaintenanceAttendance.where(user: other, maintenance_session: session).count
  end
end
