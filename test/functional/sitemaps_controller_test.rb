require "test_helper"

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

    assert_includes locs, root_url
    assert_includes locs, shows_url
    assert_includes locs, static_url("accessibility")
  end

  test "a public show is listed and a private one is not" do
    public_show = FactoryBot.create(:show, is_public: true)
    private_show = FactoryBot.create(:show, is_public: false)

    get section_sitemap_path("events")

    assert_includes locs, show_url(public_show)
    assert_not_includes locs, show_url(private_show)
    assert_select "url > lastmod", minimum: 1
  end

  # A sitemap URL that 403s the crawler is worse than an omitted one.
  test "every event URL listed actually answers 200 to a guest" do
    FactoryBot.create(:show, is_public: true)

    get section_sitemap_path("events")

    locs.first(5).each do |loc|
      get URI.parse(loc).path
      assert_response :success, "#{loc} is in the sitemap but did not render for a guest"
    end
  end

  test "a member is listed only with a public profile" do
    public_member = FactoryBot.create(:user, public_profile: true)
    private_member = FactoryBot.create(:user, public_profile: false)

    get section_sitemap_path("members")

    assert_includes locs, user_url(public_member)
    assert_not_includes locs, user_url(private_member)
  end

  private

  def locs
    Nokogiri::XML(response.body).css("url > loc").map(&:text)
  end
end
