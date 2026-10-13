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

  test "a new event's slug follows its name" do
    visit new_admin_show_path

    fill_in "event_name", with: "Brand New Show"
    assert_field "event_slug", with: "brand-new-show"
  end

  test "a new item re-rendered after a failed save still follows its name" do
    visit new_admin_news_path

    fill_in "event_name", with: "First Title"
    # Past the browser's required check, so the server answers with the form.
    page.execute_script("document.querySelector('form#new_news').noValidate = true")
    click_on "Create News"
    assert_text "Please review the problems below"
    assert_field "event_slug", with: "first-title"

    fill_in "event_name", with: "Second Title"
    assert_field "event_slug", with: "second-title"
  end

  # The slug is the event's URL, so a rename must not move it.
  test "renaming an existing event leaves its slug alone" do
    show = FactoryBot.create(:show, name: "Original Name")
    visit edit_admin_show_path(show)

    fill_in "event_name", with: "Renamed Show"
    assert_field "event_name", with: "Renamed Show"
    assert_field "event_slug", with: "original-name"
  end
end
