require "application_system_test_case"

# The Buy Tickets modal, driven without ever contacting the real ticket shop.
#
# The controller's base URL is repointed at the test app first, so pretix's own script 404s and
# never loads; a stand-in stub takes its place. The stub reproduces the one pretix behaviour the
# controller has to work around: building a widget *replaces* the <pretix-widget> element with a
# rendered wrapper that carries its attributes. Without that, a test cannot tell a controller
# that rebuilds the element from one that re-labels markup pretix has already consumed — both
# look identical while the element is still sitting there untouched.
class PretixModalTest < ApplicationSystemTestCase
  FAKE_PRETIX = <<~JS.freeze
    window.PretixWidget = {
      widget_data: {},
      buildWidgets() {
        document.querySelectorAll("pretix-widget").forEach((element) => {
          const wrapper = document.createElement("div")
          wrapper.className = "pretix-widget-wrapper"
          for (const { name, value } of element.attributes) wrapper.setAttribute(name, value)
          wrapper.textContent = "tickets for " + element.getAttribute("event")
          element.replaceWith(wrapper)
        })
      }
    }
  JS

  setup do
    @rocky = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true,
                                      pretix_shown: true, start_date: Date.current,
                                      end_date: 1.week.from_now)
    @cabaret = FactoryBot.create(:show, name: "Cabaret", is_public: true,
                                        pretix_shown: true, start_date: Date.current,
                                        end_date: 1.week.from_now)
  end

  test "opening the modal shows a widget for the show that was clicked" do
    visit_home_with_fake_pretix

    buy_tickets_for(@rocky)
    pretix_finishes_loading

    assert_selector "#pretix-modal[open]"
    assert_selector "#pretix-modal h5", text: @rocky.name
    assert_selector "#pretix-modal", text: "tickets for #{shop_url_for(@rocky)}"
  end

  test "reopening for a different show rebuilds the widget instead of relabelling a spent one" do
    visit_home_with_fake_pretix

    buy_tickets_for(@rocky)
    pretix_finishes_loading
    assert_selector "#pretix-modal", text: "tickets for #{shop_url_for(@rocky)}"
    close_modal

    buy_tickets_for(@cabaret)

    assert_selector "#pretix-modal h5", text: @cabaret.name
    assert_selector "#pretix-modal", text: "tickets for #{shop_url_for(@cabaret)}"
    assert_no_text "tickets for #{shop_url_for(@rocky)}"
  end

  test "the header stays on screen however tall the widget's content grows" do
    visit_home_with_fake_pretix
    buy_tickets_for(@rocky)

    # The widget swapping its event list for a product list makes the body several screens tall,
    # and pretix scrolls its own widget into view — which used to carry the Close button off the
    # top of the viewport with it, leaving no visible way out of the modal.
    page.execute_script(<<~JS)
      const body = document.querySelector('.pretix-modal-body')
      body.insertAdjacentHTML('beforeend', '<div id="tall" style="height: 5000px">tall</div>')
      document.getElementById('tall').scrollIntoView()
    JS

    assert_selector ".pretix-modal-close", visible: true
    assert page.evaluate_script("document.querySelector('.pretix-modal-close').getBoundingClientRect().top >= 0"),
           "the Close button was scrolled out of the viewport"
  end

  test "reopening a show whose widget could not be built retries rather than reshowing an empty dialog" do
    visit_home_with_fake_pretix
    # The shop is unreachable: with no stand-in the controller goes looking for the real script,
    # and the URL it was pointed at 404s.
    page.execute_script("delete window.PretixWidget")

    buy_tickets_for(@rocky)
    assert_selector "#pretix-modal", text: "could not be loaded"
    close_modal

    page.execute_script(FAKE_PRETIX)
    buy_tickets_for(@rocky)

    assert_selector "#pretix-modal", text: "tickets for #{shop_url_for(@rocky)}"
  end

  private

  # Any origin that will not actually serve a pretix widget does; the app's own host is
  # convenient because it is definitely reachable and definitely 404s these paths.
  def fake_shop_url
    "http://#{page.server.host}:#{page.server.port}/not-a-real-shop/"
  end

  def visit_home_with_fake_pretix
    visit root_path
    page.execute_script(
      "document.querySelector('[data-controller~=\"pretix-modal\"]')" \
      ".setAttribute('data-pretix-modal-base-url-value', '#{fake_shop_url}')"
    )
    page.execute_script(FAKE_PRETIX)
  end

  # The real script builds whatever is already on the page as soon as it loads, which is what
  # consumes the first widget. Nothing announces later ones.
  def pretix_finishes_loading
    page.execute_script("window.PretixWidget.buildWidgets()")
  end

  def shop_url_for(show)
    "#{fake_shop_url}#{show.pretix_slug}/"
  end

  def buy_tickets_for(show)
    find("button[data-pretix-modal-slug-param='#{show.pretix_slug}']", match: :first).click
  end

  def close_modal
    find(".pretix-modal-close").click
    assert_no_selector "#pretix-modal[open]"
  end
end
