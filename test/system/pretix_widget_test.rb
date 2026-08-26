require "application_system_test_case"

# The widget embedded in a show page, driven without ever contacting the real ticket shop.
#
# Every one of these arrives at the show page the way a visitor does — through Turbo, without a
# full page load — because that is the case the widget kept failing. pretix's script builds every
# <pretix-widget> on the page once, when it runs; Turbo appends that script to the head *before*
# it swaps the body in, and never re-runs it on a later visit because the tag is already there.
class PretixWidgetTest < ApplicationSystemTestCase
  # Stands in for pretix's script, reproducing the one behaviour the controller has to work
  # around: building a widget *replaces* the <pretix-widget> element with rendered markup that
  # carries its attributes. Without that, a test cannot tell a controller that builds a widget
  # from one that leaves the element sitting there untouched.
  FAKE_PRETIX = <<~JS.freeze
    window.pretixBuilds = 0
    window.PretixWidget = {
      build_widgets: true,
      widget_data: {},
      buildWidgets() {
        document.querySelectorAll("pretix-widget").forEach((element) => {
          const wrapper = document.createElement("div")
          wrapper.className = "pretix-widget-wrapper"
          // Numbering each build is what tells a rebuilt widget from markup that merely looks
          // like one — Turbo restores the spent copy from its cache, and it reads identically.
          wrapper.dataset.build = ++window.pretixBuilds
          wrapper.textContent = "tickets for " + element.getAttribute("event") +
                                " as a " + element.getAttribute("list-type")
          element.replaceWith(wrapper)
        })
      }
    }
  JS

  setup do
    @rocky = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true,
                                      pretix_shown: true, pretix_view: "list",
                                      start_date: Date.current, end_date: 1.week.from_now)
    @cabaret = FactoryBot.create(:show, name: "Cabaret", is_public: true,
                                        pretix_shown: true, pretix_view: "week",
                                        start_date: Date.current, end_date: 1.week.from_now)
  end

  test "a show reached without a full page load still builds its widget" do
    arrive_with_fake_pretix

    turbo_visit show_path(@rocky)

    assert_selector "[data-build='1']", text: "tickets for #{shop_url_for(@rocky)} as a list"
  end

  test "a second show visited in the same session gets its own widget" do
    arrive_with_fake_pretix

    turbo_visit show_path(@rocky)
    assert_selector "[data-build='1']", text: "tickets for #{shop_url_for(@rocky)}"

    turbo_visit show_path(@cabaret)

    assert_selector "[data-build='2']", text: "tickets for #{shop_url_for(@cabaret)} as a week"
    assert_no_text "tickets for #{shop_url_for(@rocky)}"
  end

  test "going back to a show rebuilds its widget rather than restoring a spent one" do
    arrive_with_fake_pretix

    turbo_visit show_path(@rocky)
    assert_selector "[data-build='1']"
    turbo_visit show_path(@cabaret)
    assert_selector "[data-build='2']"

    # Turbo caches the body it is leaving, which by then holds pretix's rendered markup rather
    # than the element it was built from — a widget that looks right and does nothing. Asserting
    # on the text alone would pass off that restored copy, so the build number is the assertion.
    page.go_back

    assert_selector "[data-build='3']", text: "tickets for #{shop_url_for(@rocky)}"
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.pretix-widget-wrapper').length")
  end

  test "a show with pretix switched off builds nothing" do
    quiet = FactoryBot.create(:show, is_public: true, pretix_shown: false,
                                     start_date: Date.current, end_date: 1.week.from_now)
    arrive_with_fake_pretix

    turbo_visit show_path(quiet)

    assert_selector "h1", text: quiet.name
    assert_no_selector ".pretix-widget-wrapper"
  end

  # Selenium hands every test in the suite the same browser, so the interception this test turns
  # on would stay on for everything that runs after it.
  teardown do
    browser = page.driver.browser
    browser.execute_cdp("Network.setBlockedURLs", urls: [])
    browser.execute_cdp("Network.disable")
  end

  private

  # Nothing here may reach the real ticket shop. The stand-in already keeps the 191 KB script
  # from being fetched, but the show page links the shop's stylesheet server-side, and an
  # implementation that stopped deferring to the stand-in would silently go to the internet.
  #
  # The sibling modal test repoints the shop URL instead; that will not work here, because the
  # show page renders its URL server-side and the widget is built the moment the page arrives.
  def block_the_ticket_shop
    browser = page.driver.browser
    browser.execute_cdp("Network.enable")
    browser.execute_cdp("Network.setBlockedURLs", urls: [ "*tickets.bedlamtheatre.co.uk*" ])
  end

  # Start on a page carrying no widget — where a visitor is before following a link to a show.
  def arrive_with_fake_pretix
    visit root_path
    block_the_ticket_shop
    page.execute_script(FAKE_PRETIX)
  end

  def turbo_visit(path)
    page.execute_script("window.Turbo.visit('#{path}')")
  end

  def shop_url_for(show)
    "https://tickets.bedlamtheatre.co.uk/#{show.pretix_slug}/"
  end
end
