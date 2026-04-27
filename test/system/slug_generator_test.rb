require "application_system_test_case"

class SlugGeneratorTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "auto-generates slug from name field on input" do
    visit new_admin_news_index_path

    fill_in "event_name", with: "My Test Event"

    assert_equal "my-test-event", find_field("event_slug").value
  end

  test "stops auto-generating slug once user manually edits it" do
    visit new_admin_news_index_path

    fill_in "event_name", with: "My Test Event"
    assert_equal "my-test-event", find_field("event_slug").value

    fill_in "event_slug", with: "custom-slug"
    fill_in "event_name", with: "Different Name"

    assert_equal "custom-slug", find_field("event_slug").value
  end

  test "handles accented characters and special punctuation correctly" do
    visit new_admin_news_index_path

    fill_in "event_name", with: "Café & Restaurant"

    assert_equal "cafe-restaurant", find_field("event_slug").value
  end

  test "resumes auto-generating after slug is cleared" do
    visit new_admin_news_index_path

    fill_in "event_name", with: "First Title"
    fill_in "event_slug", with: "manual-override"
    assert_equal "manual-override", find_field("event_slug").value

    # Clearing the slug puts auto-generation back in control
    fill_in "event_slug", with: ""
    fill_in "event_name", with: "Second Title"

    assert_equal "second-title", find_field("event_slug").value
  end
end
