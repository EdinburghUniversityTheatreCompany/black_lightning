require "application_system_test_case"

class FormValidatorTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "adds is-invalid class to required input that starts empty" do
    visit new_admin_news_path

    # Wait until the controller has run its initial pass.
    assert_selector "input#event_name.is-invalid", wait: 2

    title_field = find_field("event_name")
    assert_includes title_field["class"].to_s.split, "is-invalid"
    refute_includes title_field["class"].to_s.split, "is-valid"
  end

  test "adds is-valid class once the user fills in a required input" do
    visit new_admin_news_path

    fill_in "event_name", with: "Valid News Title"

    # Stimulus updates the class synchronously on input, but Capybara needs a
    # moment for the JS event loop to settle.
    assert_selector "input#event_name.is-valid", wait: 2

    title_field = find_field("event_name")
    assert_includes title_field["class"].to_s.split, "is-valid"
    refute_includes title_field["class"].to_s.split, "is-invalid"
  end

  test "respects server-side errors and clears them on first interaction" do
    visit new_admin_news_path

    click_button "Create News"

    assert_selector "input#event_name.is-invalid", wait: 5

    fill_in "event_name", with: "Now It Is Valid"

    assert_selector "input#event_name.is-valid", wait: 2

    title_field = find_field("event_name")
    assert_includes title_field["class"].to_s.split, "is-valid"
    refute_includes title_field["class"].to_s.split, "is-invalid"
  end
end
