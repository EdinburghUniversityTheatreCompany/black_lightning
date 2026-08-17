require "test_helper"

# The pretix widget's stylesheet is fetched from the ticket shop's own domain. Browsers enforce
# style-src-elem separately from style-src for <link> elements, so a shop origin missing from
# either directive silently costs the widget all of its styling — the same end result as the
# 404ing pretix.eu URL this replaced, and just as invisible server-side.
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  SHOP_ORIGIN = "https://tickets.bedlamtheatre.co.uk".freeze

  setup do
    get "/"
    @csp = directives(response.headers["Content-Security-Policy"])
  end

  test "the ticket shop may serve stylesheets" do
    assert_includes @csp.fetch("style-src"), SHOP_ORIGIN
    assert_includes @csp.fetch("style-src-elem"), SHOP_ORIGIN
  end

  test "the ticket shop may serve the widget script and be framed for checkout" do
    assert_includes @csp.fetch("script-src"), SHOP_ORIGIN
    assert_includes @csp.fetch("frame-src"), SHOP_ORIGIN
    assert_includes @csp.fetch("connect-src"), SHOP_ORIGIN
  end

  private

  def directives(header)
    assert_not_nil header, "no Content-Security-Policy header was sent"

    header.split(";").filter_map do |directive|
      name, *sources = directive.split
      [ name, sources ] if name
    end.to_h
  end
end
