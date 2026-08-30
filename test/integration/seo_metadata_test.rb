require "test_helper"

# The tags a crawler and a link-preview scraper actually read, asserted against the rendered
# layout rather than the helper -- the bug these replace was a timing one between a before_action
# and the action, which a helper-level test cannot see.
class SeoMetadataTest < ActionDispatch::IntegrationTest
  setup do
    @show = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true)
  end

  test "a show page captions its social preview with the show, not the venue" do
    get show_path(@show)

    assert_response :success
    assert_select "meta[property='og:title'][content=?]", "The Rocky Horror Show"
    assert_select "title", "The Rocky Horror Show | Bedlam Theatre"
  end

  test "a show page carries a twitter card pointing at the show artwork" do
    get show_path(@show)

    assert_select "meta[name='twitter:card'][content='summary_large_image']"
    assert_select "meta[name='twitter:title'][content=?]", "The Rocky Horror Show"
  end

  test "every public page declares og:type and og:site_name" do
    get root_path

    assert_select "meta[property='og:type'][content='website']"
    assert_select "meta[property='og:site_name'][content='Bedlam Theatre']"
  end

  test "a page canonicalises to itself" do
    get show_path(@show)

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{show_path(@show)}"
  end

  test "og:url agrees with the canonical" do
    get show_path(@show)

    canonical = css_select("link[rel=canonical]").first["href"]
    assert_equal canonical, css_select("meta[property='og:url']").first["content"]
  end

  # Ransack's q[...] space is unbounded -- every author, company and venue is its own URL, and
  # each combines with pagination. Collapsing it onto the unfiltered page is what stops those
  # competing with the page they filter.
  test "a ransack-filtered index canonicalises to the unfiltered index" do
    get archives_events_path, params: { q: { author_cont: "Richard O'Brien" } }

    assert_response :success
    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{archives_events_path}"
  end

  test "pagination keeps its own canonical, because page two is not page one" do
    get archives_events_path, params: { page: "2" }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{archives_events_path}?page=2"
  end

  test "a filtered and paginated index drops only the filter" do
    get archives_events_path, params: { page: "3", q: { author_cont: "Someone" } }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{archives_events_path}?page=3"
  end

  test "the show description is truncated to fit a search result" do
    long = FactoryBot.create(:show, is_public: true, publicity_text: "Brad and Janet. " * 80)

    get show_path(long)

    content = css_select("meta[name=description]").first["content"]
    assert_operator content.length, :<=, MetaHelper::DESCRIPTION_LIMIT
  end

  test "the homepage has exactly one h1" do
    get root_path

    assert_select "h1", 1
  end
end
