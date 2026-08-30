require "test_helper"

# Duplicate content, the SEO sense: two URLs that a search engine has to choose between.
#
# The 2026-08-30 audit found 20 pages titled "Bedlam Theatre" and 282 of 491 sharing one meta
# description. Those are fixed, and this is the ratchet that keeps them fixed -- adding a page
# that forgets its @title now fails here rather than a year later in Search Console.
class SeoDuplicationTest < ActionDispatch::IntegrationTest
  GENERIC_DESCRIPTION = "The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh.".freeze

  # The pages a person would actually search for. Deliberately a literal list rather than a route
  # sweep: a sweep would drag in every admin and Devise page and quietly rot into a skip list.
  def public_pages
    # The archive indexes are here because leaving them out is what let /shows and
    # /archives/shows ship with identical titles: two different listings competing on one name.
    fixed = [ root_path, events_path, shows_path, workshops_path, seasons_path,
              news_index_path, venues_path, archives_index_path, get_involved_opportunities_path,
              new_get_involved_opportunity_path,
              archives_events_path, archives_shows_path, archives_workshops_path, archives_seasons_path ]

    fixed + StaticController::PAGE_TITLES.keys.map { |page| static_path(page) }
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

  def rendered_pages
    public_pages.filter_map { |path| head_of(path) }
  end

  test "no two public pages share a title" do
    pages = rendered_pages
    assert_operator pages.length, :>=, 10, "too few pages rendered for this to prove anything"

    duplicates = pages.group_by { |page| page[:title] }.select { |_, group| group.length > 1 }

    assert_empty duplicates.transform_values { |group| group.map { |page| page[:path] } },
                 "pages sharing a <title>"
  end

  test "no public page falls back to the bare site name as its title" do
    offenders = rendered_pages.select { |page| page[:title] == "Bedlam Theatre" && page[:path] != root_path }

    assert_empty offenders.map { |page| page[:path] },
                 "pages with no title of their own"
  end

  test "no two public pages share a meta description" do
    pages = rendered_pages

    duplicates = pages.group_by { |page| page[:description] }.select { |_, group| group.length > 1 }

    assert_empty duplicates.transform_values { |group| group.map { |page| page[:path] } },
                 "pages sharing a meta description"
  end

  test "the boilerplate description is a fallback, not the site's answer for its main pages" do
    generic = rendered_pages.select { |page| page[:description] == GENERIC_DESCRIPTION }

    assert_operator generic.length, :<=, 1,
                    "#{generic.length} main pages carry the site-wide boilerplate: #{generic.map { |p| p[:path] }}"
  end

  test "every public page canonicalises to itself" do
    rendered_pages.each do |page|
      assert_equal "http://www.example.com#{page[:path]}", page[:canonical],
                   "#{page[:path]} does not canonicalise to itself"
    end
  end

  # The canonical exists to collapse duplicates, so it must not create one: ?page=1 is the same
  # content as no page parameter at all.
  test "page one canonicalises to the unparameterised url" do
    get shows_path, params: { page: "1" }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{shows_path}"
  end

  test "a later page keeps its own canonical" do
    get shows_path, params: { page: "2" }

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{shows_path}?page=2"
  end

  # Two shows of the same name in different years are different productions, and each needs a
  # title a person can tell apart in a result list.
  test "two runs of the same show do not share a title" do
    first = FactoryBot.create(:show, name: "Twelfth Night", slug: "twelfth-night-2019", is_public: true,
                                     start_date: Date.new(2019, 3, 1), end_date: Date.new(2019, 3, 4))
    second = FactoryBot.create(:show, name: "Twelfth Night", slug: "twelfth-night-2024", is_public: true,
                                      start_date: Date.new(2024, 3, 1), end_date: Date.new(2024, 3, 4))

    titles = [ first, second ].map do |show|
      get show_path(show)
      css_select("title").first.text.strip
    end

    assert_equal titles.uniq.length, titles.length, "both runs render the same title: #{titles.inspect}"
  end

  # robots.txt is matched against the URL a crawler actually sees, and Ransack's parameters arrive
  # percent-encoded (?q%5Bauthor_cont%5D=...), so a rule written only as q[ would never fire.
  test "robots.txt disallows the ransack space in its encoded form" do
    get "/robots.txt"

    assert_match(/Disallow: \/\*\?\*q%5B/, response.body)
    assert_match(/Disallow: \/\*&q%5B/, response.body)
  end

  # The two maps are the allow-list and the copy for the same set of pages; a page in one and not
  # the other is either untitled or undescribed.
  test "every static page has both a title and a description" do
    assert_equal StaticController::PAGE_TITLES.keys.sort,
                 StaticController::PAGE_DESCRIPTIONS.keys.sort
  end

  # routes.rb serves a season from /seasons/:slug and again from the short /:slug catch-all, so
  # the same content has two URLs. Both must name the same canonical or they compete.
  test "a season reached by its short url canonicalises to the long one" do
    season = FactoryBot.create(:season, name: "Bedlam Fringe 1999", is_public: true)

    get "/#{season.slug}"

    assert_response :success
    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{season_path(season)}"
  end

  test "a season reached by its long url canonicalises to itself" do
    season = FactoryBot.create(:season, name: "Bedlam Fringe 2001", is_public: true)

    get season_path(season)

    assert_select "link[rel=canonical][href=?]", "http://www.example.com#{season_path(season)}"
  end
end
