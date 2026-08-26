require "test_helper"

class Display::PagesControllerTest < ActionController::TestCase
  # Anthias plays a fixed playlist of URLs forever, so a page that renders
  # nothing is not a blank page for a moment -- it is a blank screen in the box
  # office until somebody notices and reconfigures the Pi. Every route has to
  # survive an empty database. This test is the feature.
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
      # Not "Bedlam": the layout's <title>Bedlam Theatre</title> satisfies that on
      # its own, so the assertion would pass with the identity partial rendering
      # nothing at all. The website address comes only from _identity.html.erb.
      assert_match "bedlamtheatre.co.uk", response.body,
                   "#{action} #{params} fell through to something other than the identity card"
    end
  end

  test "every display page renders with content present" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 3)

    PAGES.each do |action, params|
      get action, params: params

      assert_response :success, "#{action} #{params} did not render"
      assert response.body.present?, "#{action} #{params} rendered a blank body"
    end
  end

  # The logo is the screen's signature, and it is the whole of the identity
  # card: a panel that loses it is a wall-mounted page with no owner on it.
  test "every display page carries the Bedlam logo" do
    PAGES.each do |action, params|
      get action, params: params

      assert_match "bedlam-logo", response.body, "#{action} #{params} rendered without the logo"
    end
  end

  test "display pages are not cached and not indexed" do
    get :whats_on

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_match "noindex", response.headers["X-Robots-Tag"]
  end

  # Substitutes for manually opening the page in a browser (Step 8 of the
  # task brief): confirms the display layout pulls in display.css -- which
  # imports only tailwind-base.css -- and never application.css, whose
  # unlayered h1-h6 rules would beat the Tailwind classes sizing this screen.
  test "display pages load the display stylesheet, not application.css" do
    get :whats_on

    assert_match(/href="[^"]*display[^"]*\.css"/, response.body)
    assert_no_match(/application[-.]?\S*\.css/, response.body)
    assert_match "Bedlam Theatre", response.body
  end

  # Substitutes for manually opening the page in a browser (Step 8 of the
  # task brief): confirms the What's On panel, not the Identity fallback, is
  # what actually renders when there is an upcoming event.
  test "whats_on renders the What's On board, not the identity card, when there is an upcoming event" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)

    get :whats_on

    assert_response :success
    assert_match "What's On", response.body
    assert_match show.name, response.body
  end

  # Substitutes for Step 8 of the task brief (open /display/next/1 in a browser
  # and scan the QR with a phone): confirms slot 1 renders in tonight mode --
  # eyebrow plus content warnings -- for an event running today, and out of
  # tonight mode for one that is not.
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

  # Substitutes for the "scan the QR with a phone" half of Step 8: confirms the
  # booking QR is inlined as a data-URI PNG, so it makes no external request and
  # cannot hit whatever SVG limitation left it blank on the Anthias player.
  test "next_event inlines the booking QR as a data-uri png" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match(%r{src="data:image/png;base64,[A-Za-z0-9+/=]+"}, response.body)
    assert_no_match(/<svg /, response.body)
  end

  # The chain guarantees a panel is *selected*; nothing guarantees it renders,
  # and the artwork variant is the only render step that reaches storage. A blob
  # row whose object has gone missing used to 500 the slot page -- on an
  # unattended screen, for as long as that event stayed in the pool.
  test "next_event still renders when the event's artwork is missing from storage" do
    Event.delete_all
    event = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)
    event.image.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png",
                       content_type: "image/png")
    ActiveStorage::Blob.service.delete(event.image.blob.key)

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match event.name, response.body
    assert_no_match(/object-cover/, response.body)
  end

  test "on_this_day still renders when the archive event's artwork is missing from storage" do
    Event.delete_all
    event = FactoryBot.create(:show, is_public: true,
                                     start_date: Date.current - 20.years,
                                     end_date: Date.current - 20.years + 2)
    event.image.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png",
                       content_type: "image/png")
    ActiveStorage::Blob.service.delete(event.image.blob.key)

    get :on_this_day

    assert_response :success
    assert_match event.name, response.body
    assert_no_match(/object-cover/, response.body)
  end

  # Substitutes for Step 7 of the task brief (open /display/news in a browser):
  # confirms the News panel, not the Identity fallback, renders when a
  # published item exists.
  test "news renders the latest published item's title" do
    News.delete_all
    article = FactoryBot.create(:news, show_public: true, publish_date: 1.day.ago, title: "Bedlam Wins Award")

    get :news

    assert_response :success
    assert_match article.title, response.body
  end

  # Substitutes for Step 7 of the task brief (open /display/tonight-credits in
  # a browser and confirm nothing overflows a 1080-tall viewport): confirms
  # the Credits panel, not a fallback further down the chain, renders a cast
  # member under Cast and a crew member under Company. The overflow behaviour
  # itself cannot be asserted from a request test -- that still needs the
  # visual pass.
  test "credits renders a cast member and a crew member under their headings" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)
    actor = FactoryBot.create(:team_member, teamwork: show, position: "Actor (Abigail)")
    crew_member = FactoryBot.create(:team_member, teamwork: show, position: "Lighting Designer")

    get :credits

    assert_response :success
    assert_match "Cast", response.body
    assert_match "Company", response.body
    # Faker names contain apostrophes ("Otha O'Reilly"), which reach the body
    # HTML-escaped -- match the escaped form or this passes or fails by luck.
    assert_match ERB::Util.html_escape(actor.user_name), response.body
    assert_match ERB::Util.html_escape(crew_member.user_name), response.body
  end

  # Substitutes for Step 7 of the task brief (open /display/get-involved in a
  # browser): confirms the Get Involved panel, not a fallback further down
  # the chain, renders when an active opportunity exists.
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

    get :get_involved

    assert_response :success
    assert_match "Get Involved", response.body
    assert_match "There are no opportunities listed right now", response.body
    assert_match "submit your own", response.body
    # A link is meaningless on a screen nobody can touch -- the QR is the call
    # to action, so the anchor goes and its words stay.
    assert_no_match %r{<a[^>]*get_involved/opportunities/new}, response.body
    # It kept its own identity rather than becoming a second What's On slide.
    assert_no_match(/What&#39;s On|What's On/, response.body)
  end

  # The panel renders for whoever is signed in on the device that fetched it,
  # and the sanitizer strips the Edit button's anchor but keeps its word.
  test "get_involved never renders the editable block's edit control" do
    OpportunityRole.delete_all
    Opportunity.delete_all
    Admin::EditableBlock.create!(
      name: Display::Panels::GetInvolved::EMPTY_STATE_BLOCK, admin_page: false,
      content: "There are no opportunities listed right now."
    )
    sign_in users(:admin)

    get :get_involved

    assert_response :success
    assert_match "There are no opportunities listed right now", response.body
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

  private

  # delete_all in child-first order: several of these associations are declared
  # restrict_with_error, and delete_all bypasses that but not the FK columns.
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
