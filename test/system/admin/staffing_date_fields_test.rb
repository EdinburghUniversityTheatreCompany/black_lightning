require "application_system_test_case"

##
# System test for the Stimulus-driven "Add Date" / "Remove" controls on the
# New Staffing form (app/javascript/controllers/staffing_date_fields_controller.js).
#
# Regression: the remove link used to be looked up via the obsolete Bootstrap
# class `a.btn-danger`, which no longer renders (buttons now use ButtonComponent
# Tailwind classes), so clicking "Add Date" threw
#   TypeError: ... querySelector(...) is null
# and the cloned row's Remove button was never wired up.
##
class Admin::StaffingDateFieldsTest < ApplicationSystemTestCase
  setup do
    # Admin has every backend permission, including creating staffings.
    @user = FactoryBot.create(:admin)
    login_as @user
  end

  test "Add Date appends a date row and Remove deletes it" do
    visit new_admin_staffing_path

    # The blueprint row is display:none, so no date rows are visible initially.
    assert_selector ".control-group.datetime", count: 0

    find("a[data-action~='click->staffing-date-fields#addDate']").click

    # A cloned, visible date row should appear (no JS error).
    assert_selector ".control-group.datetime", count: 1

    within(".control-group.datetime") do
      find("a[data-action~='click->staffing-date-fields#removeDate']").click
    end

    # The row is removed again.
    assert_selector ".control-group.datetime", count: 0
  end
end
