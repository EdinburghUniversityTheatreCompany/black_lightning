require "application_system_test_case"

# The layout's flash alerts show their messages as text: they interpolate names people type and
# values from the URL.
class FlashAlertsTest < ApplicationSystemTestCase
  include ClimateTestHelpers

  setup { login_as users(:admin) }

  test "a success toast shows markup in a name as text" do
    sensor = create_climate_sensor(display_name: "<b>x</b>")

    visit edit_admin_climate_sensor_path(sensor)
    click_on "Save"

    assert_selector ".swal2-container", text: "<b>x</b> updated."
    assert_no_selector ".swal2-container b"
  end

  test "an error alert shows markup from the URL as text" do
    visit admin_reimbursements_budgets_path(cost_centre: "<b>x</b>")

    assert_selector ".swal2-popup", text: "There's no cost centre called \"<b>x</b>\"."
    assert_no_selector ".swal2-popup b"
    assert_equal "justify", evaluate_script("getComputedStyle(document.querySelector('.swal2-popup .text-justify')).textAlign")
  end

  test "several messages of one type are listed, in the error alert and in a toast" do
    visit admin_tests_test_alerts_path(type: "error")

    assert_selector ".swal2-popup li", count: 3
    assert_selector ".swal2-popup li", text: "This is an alert message that should be added to the errors"

    visit admin_tests_test_alerts_path(type: "success")

    assert_selector ".swal2-container li", count: 3
  end
end
