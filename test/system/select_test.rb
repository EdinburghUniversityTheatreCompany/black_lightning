require "application_system_test_case"

# Tom Select initialisation and remote loading in the Stimulus select controller.
class SelectTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "a remote select initialises with its placeholder and loads options as the user types" do
    visit new_admin_debt_checker_path

    assert_equal "Search by name...", find(".ts-control .items-placeholder", visible: :any, wait: 3)["placeholder"]
    find(".ts-control").click
    find(".ts-dropdown .dropdown-input", wait: 3).set("Pet") # users(:admin) is Peter Peanut

    assert_selector ".ts-dropdown-content .option", wait: 5
  end

  test "merge page initialises tom-select for source user field" do
    @user = users(:admin)
    visit merge_admin_user_path(@user)

    assert_selector ".ts-wrapper", wait: 3
  end
end
