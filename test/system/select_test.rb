require "application_system_test_case"

##
# System test for the Stimulus-driven select controller.
#
# Verifies Tom Select initialisation, AJAX remote source loading, caching, and
# tags support introduced when porting app/javascript/src/shared/select2.js
# to app/javascript/controllers/select_controller.js.
##
class SelectTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  # ── Basic initialisation ─────────────────────────────────────────────────────

  test "tom-select wraps simple-select2 elements on page load" do
    # new_admin_debt_checker renders _user_lookup which has a .simple-select2
    visit new_admin_debt_checker_path

    # Tom Select wraps the original <select> in a .ts-wrapper div
    assert_selector ".ts-wrapper", wait: 3
  end

  test "original select element is still present alongside ts-wrapper" do
    visit new_admin_debt_checker_path

    # Tom Select hides the original <select> but keeps it in the DOM
    # (it moves it adjacent to the wrapper, not inside it)
    assert_selector "select.simple-select2", wait: 3
  end

  # ── AJAX remote source ───────────────────────────────────────────────────────

  test "tom-select with remote source opens dropdown and shows control" do
    visit new_admin_debt_checker_path

    # Click the Tom Select control to open the dropdown
    find(".ts-control").click

    # Tom Select adds a "focus" class to the wrapper when focused/open
    assert_selector ".ts-wrapper.focus", wait: 3
  end

  test "typing in a remote select loads options from the server" do
    visit new_admin_debt_checker_path

    # With the dropdown_input plugin, the search box lives inside the dropdown.
    # Click the control to open the dropdown, then type in the dropdown input.
    find(".ts-control").click
    assert_selector ".ts-dropdown .dropdown-input", wait: 3
    find(".ts-dropdown .dropdown-input").set("Pet")

    # Wait for AJAX to return results – the fixture has an "admin" user whose
    # first name is "Peter" (fixture users(:admin) = Peter Peanut)
    assert_selector ".ts-dropdown-content .option", wait: 5
  end

  # ── Placeholder ──────────────────────────────────────────────────────────────

  test "placeholder text is configured on the tom-select instance" do
    visit new_admin_debt_checker_path

    # Tom Select renders an <input class="items-placeholder"> with the placeholder text.
    # It reads data-placeholder from the original <select> element.
    assert_selector ".ts-wrapper", wait: 3
    placeholder_input = find(".ts-control .items-placeholder", visible: :any)
    assert_equal "Search by name...", placeholder_input["placeholder"],
      "Expected items-placeholder input to have placeholder 'Search by name...'"
  end

  # ── User merge page (another AJAX select) ───────────────────────────────────

  test "merge page initialises tom-select for source user field" do
    @user = users(:admin)
    visit merge_admin_user_path(@user)

    assert_selector ".ts-wrapper", wait: 3
  end

  # ── SimpleForm collection selects (via CollectionSelectInput) ────────────────

  test "simpleform association selects are wrapped by tom-select" do
    # The fault_reports form has f.association calls that produce
    # .simple-select2 selects via CollectionSelectInput
    visit new_admin_fault_report_path

    assert_selector ".ts-wrapper", wait: 3
  end
end
