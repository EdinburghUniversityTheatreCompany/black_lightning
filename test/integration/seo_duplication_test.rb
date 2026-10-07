require "test_helper"

# Duplicate titles, descriptions and canonicals across pages. Adding a page that forgets its
# @title fails here rather than a year later in Search Console.
class SeoDuplicationTest < ActionDispatch::IntegrationTest
  # The pages a person would search for: a literal list, because a route sweep would drag in every
  # admin and Devise page and rot into a skip list.
  def public_pages
    fixed = [ root_path, events_path, shows_path, workshops_path, seasons_path,
              news_index_path, venues_path, archives_index_path, get_involved_opportunities_path,
              new_get_involved_opportunity_path,
              archives_events_path, archives_shows_path, archives_workshops_path, archives_seasons_path ]

    # welcome_week is claimed by an earlier redirect route, so its template is never reached.
    static = StaticController::PAGE_TITLES.keys - [ "welcome_week" ]

    fixed + static.map { |page| static_path(page) }
  end

  def head_of(path)
    get path

    return nil if response.redirect? || !response.successful?

    {
      path: path,
      title: css_select("title").first&.text.to_s.strip,
      description: css_select("meta[name=description]").first&.[]("content").to_s.strip,
      canonical: css_select("link[rel=canonical]").first&.[]("href").to_s.strip
    }
  end

  # A page that stops rendering must fail loudly, not drop out of the assertions below.
  def rendered_pages
    pages = public_pages.to_h { |path| [ path, head_of(path) ] }

    assert_empty pages.select { |_, head| head.nil? }.keys,
                 "these pages no longer render, so nothing below is checking them"

    pages.values
  end

  def duplicates_of(pages, key)
    pages.group_by { |page| page[key] }.select { |_, group| group.length > 1 }
         .transform_values { |group| group.map { |page| page[:path] } }
  end

  # The homepage carries the bare site name and the generic description, so a page that forgot
  # its own collides with it here.
  test "public pages have distinct titles and descriptions and canonicalise to themselves" do
    pages = rendered_pages
    assert_operator pages.length, :>=, 10, "too few pages rendered for this to prove anything"

    assert_empty duplicates_of(pages, :title), "pages sharing a <title>"
    assert_empty duplicates_of(pages, :description), "pages sharing a meta description"

    pages.each do |page|
      assert_equal "http://www.example.com#{page[:path]}", page[:canonical],
                   "#{page[:path]} does not canonicalise to itself"
    end
  end

  # ?page=1 is the same content as no page parameter, so it must not get its own canonical.
  test "page one canonicalises to the unparameterised url" do
    get shows_path, params: { page: "1" }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{shows_path}"
  end

  # routes.rb serves a season from /seasons/:slug and the short /:slug catch-all; both must name
  # the same canonical.
  test "a season canonicalises to its long url from both urls" do
    season = FactoryBot.create(:season, name: "Bedlam Fringe 1999", is_public: true)
    canonical = "http://www.example.com#{season_path(season)}"

    get "/#{season.slug}"

    assert_response :success
    assert_select "link[rel=canonical][href=?]", canonical

    get season_path(season)

    assert_select "link[rel=canonical][href=?]", canonical
  end
end
