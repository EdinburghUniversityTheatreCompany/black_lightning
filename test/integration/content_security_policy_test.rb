require "test_helper"

# The pretix widget's stylesheet comes from the shop's domain. Browsers enforce style-src-elem
# separately from style-src for <link>, so a shop origin missing from either silently unstyles it.
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  SHOP_ORIGIN = "https://tickets.bedlamtheatre.co.uk".freeze

  setup do
    get "/"
    @csp = directives(response.headers["Content-Security-Policy"])
  end

  test "the ticket shop may serve stylesheets and the widget script, and be framed for checkout" do
    %w[style-src style-src-elem script-src frame-src connect-src].each do |directive|
      assert_includes @csp.fetch(directive), SHOP_ORIGIN, directive
    end
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
