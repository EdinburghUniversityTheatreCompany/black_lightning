require "test_helper"

# There was no sitemap at all: /sitemap.xml 404ed and robots.txt named none, leaving 164 pages of
# archive pagination as the only route in.
class SitemapsControllerTest < ActionDispatch::IntegrationTest
  test "the index lists one sitemap per section" do
    get sitemap_path

    assert_response :success
    assert_equal "application/xml", response.media_type

    doc = Nokogiri::XML(response.body)
    locs = doc.css("sitemapindex > sitemap > loc").map(&:text)

    assert_equal SitemapsController::SECTIONS.length, locs.length
    SitemapsController::SECTIONS.each do |section|
      assert(locs.any? { |loc| loc.end_with?("/sitemaps/#{section}.xml") }, "#{section} missing")
    end
  end

  test "every section renders a valid urlset" do
    SitemapsController::SECTIONS.each do |section|
      get section_sitemap_path(section)

      assert_response :success, "#{section} did not render"
      doc = Nokogiri::XML(response.body)
      assert_equal "urlset", doc.root.name
      assert_empty doc.errors, "#{section} produced malformed XML"
    end
  end

  test "an unknown section is a 404 rather than an empty sitemap" do
    get section_sitemap_path("passwords")

    assert_response :not_found
  end

  test "the pages section lists the hubs and the static pages" do
    get section_sitemap_path("pages")

    locs = Nokogiri::XML(response.body).css("url > loc").map(&:text)

    assert_includes locs, root_url
    assert_includes locs, shows_url
    assert_includes locs, static_url("accessibility")
  end

  test "a public show is listed and a private one is not" do
    public_show = FactoryBot.create(:show, is_public: true)
    private_show = FactoryBot.create(:show, is_public: false)

    get section_sitemap_path("events")

    locs = Nokogiri::XML(response.body).css("url > loc").map(&:text)
    assert_includes locs, show_url(public_show)
    assert_not_includes locs, show_url(private_show)
  end

  # A sitemap that advertises a URL answering 403 to the crawler reading it is worse than one
  # that omits it.
  test "every event URL listed actually answers 200 to a guest" do
    FactoryBot.create(:show, is_public: true)

    get section_sitemap_path("events")
    locs = Nokogiri::XML(response.body).css("url > loc").map(&:text)

    locs.first(5).each do |loc|
      get URI.parse(loc).path
      assert_response :success, "#{loc} is in the sitemap but did not render for a guest"
    end
  end

  test "members who kept their profile public are listed" do
    public_member = FactoryBot.create(:user, public_profile: true)

    get section_sitemap_path("members")

    locs = Nokogiri::XML(response.body).css("url > loc").map(&:text)
    assert_includes locs, user_url(public_member)
  end

  test "a member who opted out of a public profile is not listed" do
    private_member = FactoryBot.create(:user, public_profile: false)

    get section_sitemap_path("members")

    locs = Nokogiri::XML(response.body).css("url > loc").map(&:text)
    assert_not_includes locs, user_url(private_member)
  end

  test "entries carry a lastmod so a crawler can skip what has not changed" do
    FactoryBot.create(:show, is_public: true)

    get section_sitemap_path("events")

    assert_select "url > lastmod", minimum: 1
  end

  test "robots.txt points at the sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_match %r{^Sitemap: https?://\S+/sitemap\.xml$}, response.body
  end

  test "robots.txt keeps crawlers out of the unbounded ransack filter space" do
    get "/robots.txt"

    assert_match(/Disallow: \/\*\?\*q\[/, response.body)
  end
end
