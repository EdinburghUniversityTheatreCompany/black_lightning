require "test_helper"

# There was no structured data anywhere -- 0 of 491 crawled pages -- which on a ticketed events
# venue is what keeps it out of Google's event rich results and the "Things to do in Edinburgh"
# surfaces entirely.
class SeoStructuredDataTest < ActionDispatch::IntegrationTest
  setup do
    @show = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true,
                                     price: "£7/£8/£10", start_date: Date.new(2026, 9, 23),
                                     end_date: Date.new(2026, 9, 26))
  end

  def documents
    css_select("script[type='application/ld+json']").map { |tag| JSON.parse(tag.text) }
  end

  def document_of_type(type)
    documents.flat_map { |doc| doc["@graph"] || [ doc ] }.find { |node| node["@type"] == type }
  end

  test "every page carries valid parseable json-ld" do
    get root_path

    tags = css_select("script[type='application/ld+json']")
    assert_operator tags.length, :>, 0, "no structured data at all"
    tags.each { |tag| assert_nothing_raised { JSON.parse(tag.text) } }
  end

  test "the venue is marked up as a performing arts theatre with its address" do
    get root_path

    venue = document_of_type("PerformingArtsTheater")
    assert_not_nil venue
    assert_equal "Bedlam Theatre", venue["name"]
    assert_equal "11B Bristo Place", venue.dig("address", "streetAddress")
    assert_equal "EH1 1EZ", venue.dig("address", "postalCode")
    assert_equal "Edinburgh", venue.dig("address", "addressLocality")
    assert_in_delta 55.946324, venue.dig("geo", "latitude"), 0.0001
  end

  test "the company is marked up with its charity number" do
    get root_path

    org = document_of_type("Organization")
    assert_equal "Edinburgh University Theatre Company", org["name"]
    assert_equal "SC015800", org.dig("identifier", "value")
  end

  test "the venue graph appears on the find us page, which is the local search landing page" do
    get static_path("accessibility")

    assert_not_nil document_of_type("PerformingArtsTheater")
  end

  test "a show is marked up as a TheaterEvent with its dates" do
    get show_path(@show)

    event = document_of_type("TheaterEvent")
    assert_not_nil event, "the show page carries no event markup"
    assert_equal "The Rocky Horror Show", event["name"]
    assert_equal "2026-09-23", event["startDate"]
    assert_equal "2026-09-26", event["endDate"]
    assert_equal "https://schema.org/EventScheduled", event["eventStatus"]
  end

  test "an event points at the venue and organiser by reference rather than repeating them" do
    get show_path(@show)

    event = document_of_type("TheaterEvent")
    venue = document_of_type("PerformingArtsTheater")

    assert_equal venue["@id"], event.dig("location", "@id")
    assert_predicate event.dig("organizer", "@id").to_s, :present?
  end

  test "a readable price becomes an aggregate offer" do
    get show_path(@show)

    offers = document_of_type("TheaterEvent")["offers"]
    assert_equal "AggregateOffer", offers["@type"]
    assert_equal "GBP", offers["priceCurrency"]
    assert_equal "7.00", offers["lowPrice"]
    assert_equal "10.00", offers["highPrice"]
  end

  # A wrong price in a rich result is a promise the box office has to honour.
  test "an unreadable price produces no offers at all rather than a guess" do
    free = FactoryBot.create(:show, is_public: true, price: "Free / pay what you want")

    get show_path(free)

    assert_nil document_of_type("TheaterEvent")["offers"]
  end

  test "a single price is both the low and the high" do
    single = FactoryBot.create(:show, is_public: true, price: "£5 on the door")

    get show_path(single)

    offers = document_of_type("TheaterEvent")["offers"]
    assert_equal "5.00", offers["lowPrice"]
    assert_equal "5.00", offers["highPrice"]
  end

  test "a show page carries a breadcrumb trail" do
    get show_path(@show)

    crumbs = document_of_type("BreadcrumbList")
    assert_not_nil crumbs
    names = crumbs["itemListElement"].map { |item| item["name"] }
    assert_equal "Home", names.first
    assert_includes names, "The Rocky Horror Show"
    assert_equal (1..names.length).to_a, crumbs["itemListElement"].map { |item| item["position"] }
  end

  test "the homepage has no breadcrumb, having nothing to trail from" do
    get root_path

    assert_nil document_of_type("BreadcrumbList")
  end

  test "a news post is marked up as a NewsArticle" do
    author = FactoryBot.create(:user)
    news = FactoryBot.create(:news, title: "Auditions open", author: author, show_public: true)

    get news_path(news)

    article = document_of_type("NewsArticle")
    assert_not_nil article
    assert_equal "Auditions open", article["headline"]
    assert_predicate article["datePublished"].to_s, :present?
  end

  test "an index page carries no event markup" do
    get shows_path

    assert_nil document_of_type("TheaterEvent")
  end

  test "a hub index lists what it is showing as an ItemList" do
    get shows_path

    list = document_of_type("ItemList")
    assert_not_nil list, "the shows index carries no ItemList"
    names = list["itemListElement"].map { |item| item["name"] }
    assert_includes names, "The Rocky Horror Show"
    assert_equal (1..names.length).to_a, list["itemListElement"].map { |item| item["position"] }
  end

  test "a show page carries no ItemList, listing nothing" do
    get show_path(@show)

    assert_nil document_of_type("ItemList")
  end
end
