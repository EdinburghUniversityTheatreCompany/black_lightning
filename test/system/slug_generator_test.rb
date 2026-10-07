require "application_system_test_case"

class SlugGeneratorTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "slug follows the name until edited by hand, and again once cleared" do
    visit new_admin_news_path

    fill_in "event_name", with: "Café & Restaurant"
    assert_field "event_slug", with: "cafe-restaurant"

    fill_in "event_slug", with: "custom-slug"
    fill_in "event_name", with: "Different Name"
    assert_field "event_slug", with: "custom-slug"

    fill_in "event_slug", with: ""
    fill_in "event_name", with: "Second Title"
    assert_field "event_slug", with: "second-title"
  end
end
