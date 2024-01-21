require 'application_system_test_case'


class Admin::MaintenanceSessionsTest < ApplicationSystemTestCase
  setup do
    @admin_maintenance_session = maintenance_sessions(:one)
    login_as users(:admin)
  end

  test "visiting the index" do
    visit admin_maintenance_sessions_url
    assert_selector "h1", text: "Maintenance Sessions"

    assert_text "REPLACE THIS WITH THE NAME OF A FIXTURE ITEM"
  end

  test "should create Maintenance session" do
    visit admin_maintenance_sessions_url
    click_on "New Maintenance Session"

    fill_in "Date", with: @admin_maintenance_session.date
    click_on "Create Maintenance session"

    assert_text 'The Maintenance session was successfully created'
  end

  test "should update Maintenance session" do
    visit admin_maintenance_session_url(@admin_maintenance_session)
    click_on "Edit", match: :prefer_exact

    fill_in "Date", with: @admin_maintenance_session.date
    click_on "Update Maintenance session"

    assert_text "The Maintenance session was successfully updated."
  end

  test "should destroy Maintenance session" do
    visit admin_maintenance_session_url(@admin_maintenance_session)

    page.accept_confirm do
      click_on 'Destroy', match: :first
    end
    assert_text "The Maintenance session has been successfully destroyed."
  end
end
