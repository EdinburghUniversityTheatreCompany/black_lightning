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
    documents_of_type(type).first
  end

  def documents_of_type(type)
    documents.flat_map { |doc| doc["@graph"] || [ doc ] }.select { |node| node["@type"] == type }
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

  # --- performances ------------------------------------------------------

  # The upgrade CLAUDE.md named as the biggest one outstanding: a date-only
  # startDate is all an event without performances can honestly claim, and it is
  # what Google gets the poorest rich result from.
  test "each performance becomes an event of its own with a real curtain time" do
    @show.update!(duration_minutes: 135)
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 24, 19, 30))
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 25, 19, 30))

    get show_path(@show)

    performances = documents_of_type("TheaterEvent").select { |node| node["superEvent"] }

    assert_equal 2, performances.length
    assert_equal "2026-09-24T19:30:00+01:00", performances.first["startDate"]
    assert_equal "2026-09-24T21:45:00+01:00", performances.first["endDate"]
  end

  test "a performance points back at the run it belongs to" do
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 24, 19, 30))

    get show_path(@show)

    run = documents_of_type("TheaterEvent").find { |node| node["superEvent"].nil? }
    performance = documents_of_type("TheaterEvent").find { |node| node["superEvent"] }

    assert_equal run["@id"], performance.dig("superEvent", "@id")
    assert_includes run["subEvent"].map { |sub| sub["@id"] }, performance["@id"]
  end

  # Every archive event has none, and must still be marked up exactly as before.
  test "an event with no performances keeps its date-only run markup" do
    get show_path(@show)

    events = documents_of_type("TheaterEvent")

    assert_equal 1, events.length
    assert_equal "2026-09-23", events.first["startDate"]
    assert_nil events.first["subEvent"]
  end

  test "an accessible performance says so in schema.org's own vocabulary" do
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 24, 19, 30),
                                         access_flags: %w[relaxed captioned])

    get show_path(@show)

    performance = documents_of_type("TheaterEvent").find { |node| node["superEvent"] }

    assert_equal %w[relaxedPerformance captions], performance["accessibilityFeature"]
  end

  # A press night is a scheduling label, not access provision. Publishing it as
  # an accessibilityFeature tells a search engine something untrue.
  test "a scheduling flag is not published as an accessibility feature" do
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 24, 19, 30),
                                         access_flags: %w[press_night preview])

    get show_path(@show)

    performance = documents_of_type("TheaterEvent").find { |node| node["superEvent"] }

    assert_nil performance["accessibilityFeature"]
  end

  test "doors open time is published when it is known" do
    @show.update!(doors_open_minutes_before: 30)
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 9, 24, 19, 30))

    get show_path(@show)

    performance = documents_of_type("TheaterEvent").find { |node| node["superEvent"] }

    assert_equal "2026-09-24T19:00:00+01:00", performance["doorTime"]
  end

  # --- structured prices -------------------------------------------------

  test "structured bands become one named offer each, not a scraped range" do
    @show.update!(ticket_prices: [
      { "category" => "standard", "amount" => "10" },
      { "category" => "concession", "amount" => "8" }
    ])

    get show_path(@show)

    offers = document_of_type("TheaterEvent")["offers"]

    assert_equal "AggregateOffer", offers["@type"]
    assert_equal "8.00", offers["lowPrice"]
    assert_equal "10.00", offers["highPrice"]
    assert_equal [ "Standard", "Concession" ], offers["offers"].map { |offer| offer["name"] }
    assert_equal [ "10.00", "8.00" ], offers["offers"].map { |offer| offer["price"] }
  end

  # The parser refused ~38% of the archive, so the old scrape has to stay.
  test "an event with no bands still falls back to reading the price string" do
    get show_path(@show)

    offers = document_of_type("TheaterEvent")["offers"]

    assert_equal "7.00", offers["lowPrice"]
    assert_equal "10.00", offers["highPrice"]
    assert_nil offers["offers"]
  end

  test "a free event is marked as free" do
    @show.update!(ticket_prices: [ { "category" => "standard", "amount" => "0" } ])

    get show_path(@show)

    assert document_of_type("TheaterEvent")["isAccessibleForFree"]
  end

  test "a paid event is not marked free" do
    @show.update!(ticket_prices: [ { "category" => "standard", "amount" => "10" } ])

    get show_path(@show)

    assert_not document_of_type("TheaterEvent")["isAccessibleForFree"]
  end

  # --- the play and who made it ------------------------------------------

  test "a show names the play it is staging and who wrote it" do
    @show.update!(author: "Richard O'Brien")

    get show_path(@show)

    work = document_of_type("TheaterEvent")["workFeatured"]

    assert_equal "Play", work["@type"]
    assert_equal "The Rocky Horror Show", work["name"]
    assert_equal "Richard O'Brien", work.dig("author", "name")
  end

  # A workshop is not a play, so claiming one would be a lie about what it is.
  test "a workshop features no play" do
    workshop = FactoryBot.create(:workshop, is_public: true, author: "Someone")

    get workshop_path(workshop)

    assert_nil document_of_type("TheaterEvent")["workFeatured"]
  end

  test "the director is named from the team" do
    director = FactoryBot.create(:user, first_name: "Ada", last_name: "Lovelace")
    FactoryBot.create(:team_member, teamwork: @show, user: director, position: "Director")

    get show_path(@show)

    assert_equal "Ada Lovelace", document_of_type("TheaterEvent").dig("director", "name")
  end

  # "Assistant Director" is not the director, and naming them as such is wrong.
  test "an assistant director is not the director" do
    assistant = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: @show, user: assistant, position: "Assistant Director")

    get show_path(@show)

    assert_nil document_of_type("TheaterEvent")["director"]
  end

  # --- running time and age ----------------------------------------------

  test "the running time and age guidance are published when set" do
    @show.update!(duration_minutes: 135, age_guidance: "14+")

    get show_path(@show)

    event = document_of_type("TheaterEvent")

    assert_equal "PT2H15M", event["duration"]
    assert_equal "14+", event["typicalAgeRange"]
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
