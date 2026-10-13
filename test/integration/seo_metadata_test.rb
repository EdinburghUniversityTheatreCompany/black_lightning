require "test_helper"

# The tags crawlers and link previews read, asserted against the rendered layout: the bug was
# before_action timing, which a helper test cannot see.
class SeoMetadataTest < ActionDispatch::IntegrationTest
  setup do
    # Dated forward on purpose: a finished run gains a year suffix (see seo_page_titles_test).
    @show = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true,
                                     start_date: Date.current + 7, end_date: Date.current + 14)
  end

  test "a show page captions its title and social preview with the show, not the venue" do
    get show_path(@show)

    assert_response :success
    assert_select "title", "The Rocky Horror Show | Bedlam Theatre"
    assert_select "meta[property='og:title'][content=?]", "The Rocky Horror Show"
    assert_select "meta[name='twitter:title'][content=?]", "The Rocky Horror Show"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
  end

  test "a page canonicalises to itself, and og:url agrees" do
    get show_path(@show)

    canonical = "http://www.example.com#{show_path(@show)}"
    assert_select "link[rel=canonical][href=?]", canonical
    assert_select "meta[property='og:url'][content=?]", canonical
  end

  # Ransack's q[...] space is unbounded; collapsing it onto the unfiltered page stops it
  # competing with the page it filters. Pagination keeps its own canonical: page 3 is not page 1.
  test "a filtered and paginated index drops only the filter" do
    get archives_events_path, params: { page: "3", q: { author_cont: "Someone" } }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{archives_events_path}?page=3"
  end

  test "the homepage has exactly one h1" do
    get root_path

    assert_select "h1", 1
  end
end
