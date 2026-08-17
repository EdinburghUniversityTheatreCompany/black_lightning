require "test_helper"

# Both places the pretix widget appears used to point at their own copy of its stylesheet: the
# show page at a vendored snapshot of a CDN that has since been retired, the Buy Tickets modal at
# a pretix.eu URL that 404s. Whether the modal looked right came down to whether Turbo happened
# to have carried the show page's stylesheet over — so both are pinned here.
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

  test "the widget is pointed at the shop with list-type, not an invalid inline style" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: true, pretix_view: "week")

    get :show, params: { id: show }

    assert_select "pretix-widget[event=?][list-type=?]",
                  "https://tickets.bedlamtheatre.co.uk/#{show.pretix_slug}/", "week"
  end

  test "a show with pretix switched off renders no widget and loads none of its assets" do
    show = FactoryBot.create(:show, is_public: true, pretix_shown: false)

    get :show, params: { id: show }

    assert_select "pretix-widget", false
    assert_no_match STYLESHEET, response.body
  end
end

class PretixModalRenderingTest < ActionController::TestCase
  tests StaticController

  test "the Buy Tickets modal ships an empty container, not a pre-baked widget" do
    upcoming_show

    get :home

    assert_response :success
    # pretix swaps the <pretix-widget> element out for its own markup the moment it builds one,
    # so a widget rendered here could only ever be configured for the first show clicked. The
    # controller creates a fresh element per open inside this container instead.
    assert_select "#pretix-modal pretix-widget", false
    assert_select "#pretix-modal [data-pretix-modal-target=?]", "widgetContainer"
  end

  test "a pretix-enabled show gets a Buy Tickets button carrying its slug" do
    show = upcoming_show

    get :home

    assert_select "button[data-pretix-modal-slug-param=?]", show.pretix_slug
  end

  private

  # The home page lists Event.current, so the show has to still be running.
  def upcoming_show
    FactoryBot.create(:show, is_public: true, pretix_shown: true,
                            start_date: Date.current, end_date: 1.week.from_now)
  end
end
