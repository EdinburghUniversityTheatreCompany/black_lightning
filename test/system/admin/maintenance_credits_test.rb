require "application_system_test_case"


class Admin::MaintenanceCreditsTest < ApplicationSystemTestCase
  setup do
    @admin_maintenance_credit = maintenance_credits(:one)
    login_as users(:admin)
  end

  test "visiting the index" do
    visit admin_maintenance_credits_url
    assert_selector "h1", text: "Maintenance Credits"

    assert_text "Iolianthe Faerie"
  end

  test "should create Maintenance credit" do
    visit admin_maintenance_credits_url
    click_on "New Maintenance Credit"

    tom_select @admin_maintenance_credit.maintenance_session.to_label.to_s, from: "Maintenance session"
    tom_select @admin_maintenance_credit.user.name, from: "User"
    click_on "Create Maintenance credit"

    assert_text "The Maintenance Credit was successfully created."
  end

  test "should update Maintenance credit" do
    visit admin_maintenance_credit_url(@admin_maintenance_credit)
    click_on "Edit", match: :prefer_exact

    tom_select @admin_maintenance_credit.maintenance_session.to_label.to_s, from: "Maintenance session"
    tom_select @admin_maintenance_credit.user.name, from: "User"
    click_on "Update Maintenance credit"

    assert_text "The Maintenance Credit was successfully updated."
  end

  test "should destroy Maintenance credit" do
    visit admin_maintenance_credit_url(@admin_maintenance_credit)

    click_on "Destroy", match: :first
    assert_selector ".swal2-popup", wait: 5
    click_button "Yes"
    assert_text "The Maintenance Credit has been successfully destroyed."
  end
end
