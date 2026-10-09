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

  test "a remote select searches afresh after a Turbo visit" do
    visit new_admin_debt_checker_path
    search_remote_select("Pet")
    assert_selector ".ts-dropdown-content .option", text: "Peter Peanut", wait: 5

    FactoryBot.create(:member, first_name: "Petunia", last_name: "Latecomer")
    execute_script("document.body.dataset.before = 'yes'; Turbo.visit(arguments[0])", new_admin_debt_checker_path)
    assert_no_selector "body[data-before]", wait: 5

    search_remote_select("Pet")
    assert_selector ".ts-dropdown-content .option", text: "Petunia Latecomer", wait: 5
  end

  test "merge page initialises tom-select for source user field" do
    @user = users(:admin)
    visit merge_admin_user_path(@user)

    assert_selector ".ts-wrapper", wait: 3
  end

  private

  def search_remote_select(query)
    find(".ts-control", wait: 3).click
    find(".ts-dropdown .dropdown-input", wait: 3).set(query)
  end
end
