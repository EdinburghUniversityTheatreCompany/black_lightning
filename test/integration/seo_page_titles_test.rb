require "test_helper"

# Static pages and editable-block subpages name themselves in the title and description.
class SeoPageTitlesTest < ActionDispatch::IntegrationTest
  test "every static page names itself in the title" do
    StaticController::PAGES.each do |page, (expected, _description)|
      get static_path(page)

      # /welcome_week is claimed by an earlier redirect route; it stays in the map as the allow-list.
      next if response.redirect?

      assert_response :success, "GET /#{page} did not render"
      assert_select "title", "#{expected} | Bedlam Theatre", "/#{page} did not name itself"
    end
  end

  test "about, get_involved and archives subpages take their title and description from the editable block" do
    [
      [ about_path(page: "committee"), "Committee", "about/committee", "The committee runs the theatre." ],
      [ get_involved_path(page: "membership"), "Getting Membership", "get_involved/membership", "How to join the EUTC." ],
      [ archives_path(page: "about"), "About the Archive", "archives/about", "Decades of student theatre." ]
    ].each do |path, name, url, content|
      Admin::EditableBlock.create!(name: name, url: url, admin_page: false, content: content)

      get path

      assert_select "title", "#{name} | Bedlam Theatre"
      assert_select "meta[name=description][content=?]", content
    end
  end

  test "the opportunities page names itself" do
    get get_involved_opportunities_path

    assert_select "title", "Opportunities | Bedlam Theatre"
  end

  # A block whose body is only a nav redirect has no prose: fall back rather than describe the
  # page as "EXTERNAL_URL https://...".
  test "a block with no usable prose falls back to the site description" do
    Admin::EditableBlock.create!(name: "Elsewhere", url: "about/elsewhere", admin_page: false, content: "")

    get about_path(page: "elsewhere")

    assert_select "meta[name=description][content=?]",
                  "The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh."
  end

  test "a finished show is disambiguated by the year it ran" do
    old_show = FactoryBot.create(:show, name: "The History Boys", is_public: true,
                                        start_date: Date.new(2019, 3, 1), end_date: Date.new(2019, 3, 4))

    get show_path(old_show)

    assert_select "title", "The History Boys (2019) | Bedlam Theatre"
  end
end
