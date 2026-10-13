require "application_system_test_case"

class FormValidatorTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "a required input starts invalid and turns valid once filled in" do
    visit new_admin_news_path

    assert_selector "input#event_name.is-invalid:not(.is-valid)", wait: 2

    fill_in "event_name", with: "Valid News Title"

    assert_selector "input#event_name.is-valid:not(.is-invalid)", wait: 2
  end
end
