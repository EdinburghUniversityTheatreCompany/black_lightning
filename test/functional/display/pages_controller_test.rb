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
      assert_match "Bedlam", response.body, "#{action} #{params} rendered nothing recognisable"
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

  # Substitutes for the "scan the QR with a phone" half of Step 8: confirms
  # the booking QR is inlined as an <svg> (no external image request, no
  # bogus <?xml comment for the HTML parser to choke on).
  test "next_event renders the booking QR as an inline svg with no xml declaration" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    get :next_event, params: { slot: "1" }

    assert_response :success
    assert_match(/<svg /, response.body)
    assert_no_match(/<\?xml/, response.body)
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
