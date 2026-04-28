require "application_system_test_case"


class Admin::MaintenanceAttendancesTest < ApplicationSystemTestCase
  setup do
    @admin_maintenance_attendance = maintenance_attendances(:one)
    login_as users(:admin)
  end

  test "visiting the index" do
    visit admin_maintenance_attendances_url
    assert_selector "h1", text: "Maintenance Attendances"

    assert_text "Iolianthe Faerie"
  end

  test "should create Maintenance attendance" do
    visit admin_maintenance_attendances_url
    click_on "New Maintenance Attendance"

    select @admin_maintenance_attendance.maintenance_session.to_label.to_s, from: "Maintenance session"
    select @admin_maintenance_attendance.user.name, from: "User"
    click_on "Create Maintenance attendance"

    assert_text "The Maintenance Attendance was successfully created."
  end

  test "should update Maintenance attendance" do
    visit admin_maintenance_attendance_url(@admin_maintenance_attendance)
    click_on "Edit", match: :prefer_exact

    select @admin_maintenance_attendance.maintenance_session.to_label.to_s, from: "Maintenance session"
    select @admin_maintenance_attendance.user.name, from: "User"
    click_on "Update Maintenance attendance"

    assert_text "The Maintenance Attendance was successfully updated."
  end

  test "should destroy Maintenance attendance" do
    visit admin_maintenance_attendance_url(@admin_maintenance_attendance)

    click_on "Destroy", match: :first
    find(".swal2-confirm").click
    assert_text "The Maintenance Attendance has been successfully destroyed."
  end
end
