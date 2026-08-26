require "test_helper"

class PretixHelperTest < ActionView::TestCase
  test "the widget stylesheet is served by the shop, not by pretix.eu" do
    # pretix.eu has no widget stylesheet at all: /widget/v1.en.css there 301s to a trailing-slash
    # URL that 404s, so a page pointing at it renders the widget with no styling whatsoever.
    assert_equal "https://tickets.bedlamtheatre.co.uk/widget/v1.css", pretix_widget_stylesheet_url
  end

  test "pretix_event_url points at the event's shop page with a trailing slash" do
    event = FactoryBot.build(:show, slug: "the-rocky-horror-show", pretix_slug_override: nil)

    assert_equal "https://tickets.bedlamtheatre.co.uk/the-rocky-horror-show/", pretix_event_url(event)
  end

  test "pretix_event_url follows the slug override" do
    event = FactoryBot.build(:show, slug: "ignored", pretix_slug_override: "rhs-2026")

    assert_equal "https://tickets.bedlamtheatre.co.uk/rhs-2026/", pretix_event_url(event)
  end

  test "pretix_shop_url with no path is the shop root" do
    assert_equal "https://tickets.bedlamtheatre.co.uk/", pretix_shop_url
  end
end
