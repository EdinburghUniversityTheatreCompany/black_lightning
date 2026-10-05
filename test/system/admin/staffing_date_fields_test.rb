require "application_system_test_case"

# The "Add Date" and "Remove" controls on the New Staffing form (staffing_date_fields_controller.js).
class Admin::StaffingDateFieldsTest < ApplicationSystemTestCase
  setup do
    @user = FactoryBot.create(:admin)
    login_as @user
  end

  test "Add Date appends a date row and Remove deletes it" do
    visit new_admin_staffing_path

    # The blueprint row is hidden.
    assert_selector ".control-group.datetime", count: 0

    find("button[data-action~='click->staffing-date-fields#addDate']").click

    assert_selector ".control-group.datetime", count: 1

    within(".control-group.datetime") do
      assert_selector "input[name='start_times[0]']"
      assert_selector "input[name='end_times[0]']"
    end

    within(".control-group.datetime") do
      find("button[data-action~='click->staffing-date-fields#removeDate']").click
    end

    assert_selector ".control-group.datetime", count: 0
  end
end
