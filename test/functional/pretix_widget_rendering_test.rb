require "test_helper"

# Both widget surfaces must take the stylesheet from the shop's own domain (pretix.eu
# 404s), or the modal's styling depends on Turbo carrying the show page's over.
class PretixWidgetRenderingTest < ActionController::TestCase
  tests ShowsController

  STYLESHEET = "https://tickets.bedlamtheatre.co.uk/widget/v1.css".freeze

  test "a pretix-enabled show links the shop's own widget stylesheet" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: true, pretix_view: "list")

    get :show, params: { id: show }

    assert_response :success
    assert_match STYLESHEET, response.body
    assert_no_match(/pretix\.eu/, response.body)
  end

  test "the widget container is pointed at the shop with list-type, not an invalid inline style" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: true, pretix_view: "week")

    get :show, params: { id: show }

    assert_select "[data-controller=?][data-pretix-widget-event-url-value=?][data-pretix-widget-list-type-value=?]",
                  "pretix-widget", "https://tickets.bedlamtheatre.co.uk/#{show.pretix_slug}/", "week"
  end

  test "the page ships an empty container and no widget script of its own" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: true)

    get :show, params: { id: show }

    # A <script> here is loaded by Turbo before the body it should build in exists, and
    # never again on a later visit (Turbo keeps the identical tag). The controller loads
    # it instead, so only our code decides when a widget is built.
    assert_no_match(/widget\/v1\.en\.js/, response.body)
    assert_select "pretix-widget", false
  end

  test "a show with pretix switched off renders no widget and loads none of its assets" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: false)

    get :show, params: { id: show }

    assert_select "[data-controller=?]", "pretix-widget", false
    assert_no_match STYLESHEET, response.body
  end
end

class PretixModalRenderingTest < ActionController::TestCase
  tests StaticController

  test "the Buy Tickets modal ships an empty container, not a pre-baked widget" do
    upcoming_show

    get :home

    assert_response :success
    # pretix swaps the <pretix-widget> element for its own markup when it builds, so one
    # rendered here could only serve the first show clicked; the controller creates a
    # fresh element per open inside this container.
    assert_select "#pretix-modal pretix-widget", false
    assert_select "#pretix-modal [data-pretix-modal-target=?]", "widgetContainer"
  end

  test "a pretix-enabled show gets a Buy Tickets button carrying its slug" do
    show = upcoming_show

    get :home

    assert_select "button[data-pretix-modal-slug-param=?]", show.pretix_slug
  end

  # A <button> with no type submits; if one ever sits inside a <form>, Buy Tickets
  # would open the modal AND submit the form.
  test "the Buy Tickets button is type=button, not a submit" do
    show = upcoming_show

    get :home

    # Both surfaces render one: the carousel caption and the What's On grid.
    assert_select "button[data-pretix-modal-slug-param=?]", show.pretix_slug do |buttons|
      assert_predicate buttons, :any?
      buttons.each { |button| assert_equal "button", button["type"] }
    end
  end

  private

  # The home page lists Event.current, so the show has to still be running.
  def upcoming_show
    FactoryBot.create(:show, is_public: true, pretix_shown: true,
                            start_date: Date.current, end_date: 1.week.from_now)
  end
end
