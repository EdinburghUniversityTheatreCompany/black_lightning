require "test_helper"

# Twenty pages -- every static page, every /about/* and /get_involved/* subpage -- rendered
# <title>Bedlam Theatre</title> and the site-wide boilerplate description. They are the pages
# that should win "Edinburgh student theatre", "student theatre auditions Edinburgh" and, for the
# Find Us page, every "theatre near me" query.
class SeoPageTitlesTest < ActionDispatch::IntegrationTest
  GENERIC_DESCRIPTION = "The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh.".freeze

  test "every static page names itself in the title" do
    StaticController::PAGE_TITLES.each do |page, expected|
      get static_path(page)

      # /welcome_week is claimed by an earlier redirect route to get_involved/welcome_week, so
      # its static template is never reached. It stays in the map because the map is also the
      # allow-list, and dropping it would change which pages the controller will render.
      next if response.redirect?

      assert_response :success, "GET /#{page} did not render"
      assert_select "title", "#{expected} | Bedlam Theatre", "/#{page} did not name itself"
    end
  end

  test "an about subpage takes its title from the editable block" do
    block = Admin::EditableBlock.create!(name: "Committee", url: "about/committee", admin_page: false, content: "The committee runs the theatre.")

    get about_path(page: "committee")

    assert_select "title", "Committee | Bedlam Theatre"
    assert_select "meta[name=description][content=?]", "The committee runs the theatre."
    block.destroy
  end

  test "a get_involved subpage takes its title from the editable block" do
    block = Admin::EditableBlock.create!(name: "Getting Membership", url: "get_involved/membership", admin_page: false, content: "How to join the EUTC.")

    get get_involved_path(page: "membership")

    assert_select "title", "Getting Membership | Bedlam Theatre"
    assert_select "meta[name=description][content=?]", "How to join the EUTC."
    block.destroy
  end

  test "an archives subpage takes its title from the editable block" do
    block = Admin::EditableBlock.create!(name: "About the Archive", url: "archives/about", admin_page: false, content: "Decades of student theatre.")

    get archives_path(page: "about")

    assert_select "title", "About the Archive | Bedlam Theatre"
    block.destroy
  end

  test "the opportunities page names itself" do
    get get_involved_opportunities_path

    assert_select "title", "Opportunities | Bedlam Theatre"
  end

  test "an editable block page does not fall back to the generic description" do
    block = Admin::EditableBlock.create!(name: "Press", url: "about/press", admin_page: false, content: "Press enquiries and our media pack.")

    get about_path(page: "press")

    assert_select "meta[name=description]" do |tags|
      assert_not_equal GENERIC_DESCRIPTION, tags.first["content"]
    end
    block.destroy
  end

  # A block whose body is only a nav redirect has no prose to describe the page with; falling
  # back beats describing the page as "EXTERNAL_URL https://...".
  test "a block with no usable prose falls back to the site description" do
    block = Admin::EditableBlock.create!(name: "Elsewhere", url: "about/elsewhere", admin_page: false, content: "")

    get about_path(page: "elsewhere")

    assert_select "meta[name=description][content=?]", GENERIC_DESCRIPTION
    block.destroy
  end

  test "the hub indexes describe themselves rather than the venue" do
    { shows_path => "Shows", news_index_path => "News", workshops_path => "Workshops",
      seasons_path => "Seasons", events_path => "Events" }.each do |path, name|
      get path

      assert_response :success
      assert_select "meta[name=description]" do |tags|
        assert_not_equal GENERIC_DESCRIPTION, tags.first["content"], "#{name} still carries the generic description"
      end
    end
  end
end
