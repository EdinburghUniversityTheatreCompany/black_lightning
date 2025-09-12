require "application_system_test_case"


class Admin::MaintenanceAttendancesTest < ApplicationSystemTestCase
  setup do
    @admin_maintenance_attendance = maintenance_attendances(:one)
    login_as users(:admin)
  end

  test "visiting the index" do
    visit admin_maintenance_attendances_url
    assert_selector "h1", text: "Maintenance Attendances"

    assert_text "REPLACE THIS WITH THE NAME OF A FIXTURE ITEM"
  end

  test "should create Maintenance attendance" do
    visit admin_maintenance_attendances_url
    click_on "New Maintenance Attendance"

    fill_in "Date", with: @admin_maintenance_attendance.date
    fill_in "User", with: @admin_maintenance_attendance.user_id
    click_on "Create Maintenance attendance"

    assert_text "The Maintenance attendance was successfully created"
  end

  test "should update Maintenance attendance" do
    visit admin_maintenance_attendance_url(@admin_maintenance_attendance)
    click_on "Edit", match: :prefer_exact

    fill_in "Date", with: @admin_maintenance_attendance.date
    fill_in "User", with: @admin_maintenance_attendance.user_id
    click_on "Update Maintenance attendance"

    assert_text "The Maintenance attendance was successfully updated."
  end

  test "should destroy Maintenance attendance" do
    visit admin_maintenance_attendance_url(@admin_maintenance_attendance)

    page.accept_confirm do
      click_on "Destroy", match: :first
    end
    assert_text "The Maintenance attendance has been successfully destroyed."
  end
end
