require "test_helper"

class Display::PagesControllerTest < ActionController::TestCase
  setup do
    # The archive slide's cursor is cache state, which no transaction rolls back.
    Rails.cache.clear
  end

  # Anthias plays these URLs forever, so a blank page is a blank box office screen
  # until somebody reconfigures the Pi. Every route must survive an empty database:
  # that test is the feature.
  PAGES = [
    [ :whats_on,     {} ],
    [ :next_event,   { slot: "1" } ],
    [ :next_event,   { slot: "6" } ],
    [ :credits,      {} ],
    [ :get_involved, {} ],
    [ :news,         {} ],
    [ :on_this_day,  {} ]
  ].freeze

  test "every display page renders against an empty database" do
    empty_the_database!

    PAGES.each do |action, params|
      get action, params: params

      assert_response :success, "#{action} #{params} did not render"
      assert response.body.present?, "#{action} #{params} rendered a blank body"
      # Not "Bedlam": the layout's <title> satisfies that on its own. The address
      # comes only from _identity.html.erb.
      assert_match "bedlamtheatre.co.uk", response.body,
                   "#{action} #{params} fell through to something other than the identity card"
      assert_match "bedlam-logo", response.body, "#{action} #{params} rendered without the logo"
    end
  end

  test "every display page renders with the display layout and headers" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 3)

    PAGES.each do |action, params|
      get action, params: params

      assert_response :success, "#{action} #{params} did not render"
      # The logo is the screen's signature.
      assert_match "bedlam-logo", response.body, "#{action} #{params} rendered without the logo"
      assert_match(/href="[^"]*display[^"]*\.css"/, response.body)
      # application.css's unlayered h1-h6 rules would beat the Tailwind sizes on this screen.
      assert_no_match(/application[-.]?\S*\.css/, response.body)
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_match "noindex", response.headers["X-Robots-Tag"]
    end
  end

  # The scroll is pure CSS, so the box and the track must both be present. A
  # `truncate` on the title would cut "The Rocky Horror Picture Show by Richard O...".
  test "whats_on renders the board in a scrolling marquee, titles wrapping" do
    show = FactoryBot.create(:show, is_public: true, name: "The Rocky Horror Picture Show by Richard O'Brien",
                                    start_date: Date.current + 1, end_date: Date.current + 2)

    get :whats_on

    assert_response :success
    assert_match "What's On", response.body
    assert_select ".display-marquee ul.display-marquee__track li span:nth-child(2)", text: show.name do |titles|
      titles.each { |title| assert_not_includes title["class"].to_s.split, "truncate" }
    end
  end

  test "next_event slot 1 renders tonight mode for an event running today" do
    event = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1,
                                      content_warnings: "Loud noises")

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match event.name, response.body
    assert_match "Tonight", response.body
    assert_match "Loud noises", response.body
  end

  test "next_event slot 1 does not render tonight mode for an event not running today" do
    event = FactoryBot.create(:show, is_public: true, start_date: Date.current + 3, end_date: Date.current + 4)

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match event.name, response.body
    assert_no_match(/Tonight/, response.body)
  end

  # A data-URI PNG: no external request, and no SVG (blank on Anthias).
  test "next_event inlines the booking QR as a data-uri png" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match(%r{src="data:image/png;base64,[A-Za-z0-9+/=]+"}, response.body)
    assert_no_match(/<svg /, response.body)
  end

  # The artwork variant is the only render step that reaches storage: a blob row
  # whose object is gone used to 500 the slot page.
  test "a panel still renders when the event's artwork is missing from storage" do
    { next_event: [ { slot: "1" }, Date.current ],
      on_this_day: [ {}, Date.current - 20.years ] }.each do |action, (params, start_date)|
      Event.delete_all
      event = FactoryBot.create(:show, is_public: true, attach_image: true,
                                       start_date: start_date, end_date: start_date + 2)
      ActiveStorage::Blob.service.delete(event.image.blob.key)

      get action, params: params

      assert_response :success, action.to_s
      assert_match event.name, response.body, action.to_s
      assert_no_match(/object-cover/, response.body, action.to_s)
    end
  end

  test "on_this_day shows a different archive show on each fetch" do
    Event.delete_all
    names = 3.times.map do |index|
      # Subtract years: Date.new raises on 29 Feb. A two-day run still covers today
      # when the start slips back to the 28th.
      start_date = Date.current - (5 + index).years
      FactoryBot.create(:show, is_public: true, attach_image: true, name: "Archive Show #{index}",
                               start_date: start_date, end_date: start_date + 2).name
    end

    rendered = names.size.times.map do
      get :on_this_day

      assert_response :success
      names.find { |name| response.body.include?(name) }
    end

    assert_equal names.sort, rendered.compact.sort,
                 "the archive slide did not work through its matches: #{rendered.inspect}"
  end

  test "news renders the latest headline and clips an over-long list rather than displacing the QR code" do
    News.delete_all
    3.times do |i|
      FactoryBot.create(:news, show_public: true, publish_date: (i + 1).days.ago,
                               title: "Headline #{i}")
    end

    get :news

    assert_response :success
    assert_match "Headline 0", response.body
    # What stops a wrong budget pushing the QR code off screen.
    assert_select "ul" do |lists|
      classes = lists.first["class"].to_s.split
      assert_includes classes, "overflow-hidden"
      assert_includes classes, "min-h-0", "without min-h-0 a flex child refuses to shrink and overflows anyway"
    end
  end

  test "credits renders a cast member and a crew member under their headings" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)
    actor = FactoryBot.create(:team_member, teamwork: show, position: "Actor (Abigail)")
    crew_member = FactoryBot.create(:team_member, teamwork: show, position: "Lighting Designer")

    get :credits

    assert_response :success
    assert_match "Cast", response.body
    assert_match "Company", response.body
    # Faker names contain apostrophes, which reach the body escaped.
    assert_match ERB::Util.html_escape(actor.user_name), response.body
    assert_match ERB::Util.html_escape(crew_member.user_name), response.body
  end

  test "get_involved renders an active opportunity's display title" do
    get :get_involved

    assert_response :success
    opportunity = opportunities(:active_opportunity)
    assert_match opportunity.display_title, response.body
  end

  test "get_involved shows the site's own empty-state copy when nothing is open, with links stripped" do
    OpportunityRole.delete_all
    Opportunity.delete_all
    Admin::EditableBlock.create!(
      name: Display::Panels::GetInvolved::EMPTY_STATE_BLOCK, admin_page: false,
      content: "There are no opportunities listed right now. Check back soon, " \
               "or [submit your own](/get_involved/opportunities/new)."
    )
    sign_in users(:admin)

    get :get_involved

    assert_response :success
    assert_match "Get Involved", response.body
    assert_match "There are no opportunities listed right now", response.body
    assert_match "submit your own", response.body
    # The anchor goes, its words stay: the QR is the call to action.
    assert_no_match %r{<a[^>]*get_involved/opportunities/new}, response.body
    # It kept its own identity rather than becoming a What's On slide.
    assert_no_match(/What&#39;s On|What's On/, response.body)
    # The sanitizer strips the Edit button's anchor but keeps its word, and the
    # page renders for whoever is signed in on the device that fetched it.
    assert_no_match(/\bEdit\b/, response.body)
  end

  test "get_involved still falls through when nothing is open and no copy exists" do
    OpportunityRole.delete_all
    Opportunity.delete_all
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 2)

    assert_not Admin::EditableBlock.exists?(name: Display::Panels::GetInvolved::EMPTY_STATE_BLOCK)

    get :get_involved

    assert_response :success
    assert_match(/What&#39;s On|What's On/, response.body)
  end

  test "credits names itself as a cast list in both the tonight and next-show cases" do
    Event.delete_all
    show = FactoryBot.create(:show, is_public: true, name: "Tonight Show",
                                    start_date: Date.current, end_date: Date.current + 1)
    FactoryBot.create(:team_member, teamwork: show, position: "Director")

    get :credits

    assert_response :success
    assert_match "Tonight&#39;s Credits", response.body

    show.update!(start_date: Date.current + 5, end_date: Date.current + 6)

    get :credits

    assert_response :success
    assert_match "Next Show&#39;s Credits", response.body
  end

  test "credits carries a QR to the digital programme, falling back to the event page" do
    Event.delete_all
    show = FactoryBot.create(:show, is_public: true, name: "Programmed Show", slug: "bare-show",
                                    start_date: Date.current, end_date: Date.current + 1,
                                    digital_programme_url: "https://example.com/programme.pdf")
    FactoryBot.create(:team_member, teamwork: show, position: "Director")

    get :credits

    assert_response :success
    assert_match "Scan for the digital programme", response.body
    # The image is a data URI, so assert on the cache entry the helper encoded.
    assert Rails.cache.exist?(DisplayHelper.qr_cache_key("https://example.com/programme.pdf")),
           "expected the QR to be encoded for the programme link"

    show.update!(digital_programme_url: nil)

    get :credits

    assert_response :success
    assert_match "Scan for more about this show", response.body
    assert_no_match "Scan for the digital programme", response.body
    assert Rails.cache.exist?(DisplayHelper.qr_cache_key("http://test.host/shows/bare-show")),
           "expected the QR to fall back to the event page"
  end

  private

  # Child-first: delete_all bypasses restrict_with_error but not the FK columns.
  def empty_the_database!
    TeamMember.delete_all
    Review.delete_all
    Picture.delete_all
    Admin::Questionnaires::Questionnaire.delete_all
    Admin::Feedback.delete_all
    Event.delete_all
    OpportunityRole.delete_all
    Opportunity.delete_all
    News.delete_all
  end
end
