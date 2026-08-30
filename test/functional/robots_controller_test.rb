require "test_helper"

# robots.txt used to live in public/, where public_file_server stamps a one-year cache-control.
# Cloudflare honoured it: the rules change deployed on 2026-08-30 was still being served from a
# 30-day-old copy and would have been for another eleven months. Serving it from the app is what
# makes a rules change actually reach a crawler.
class RobotsControllerTest < ActionDispatch::IntegrationTest
  test "robots.txt is served as plain text" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "it is cacheable but not for a year" do
    get "/robots.txt"

    cache_control = response.headers["Cache-Control"].to_s
    assert_includes cache_control, "public"

    max_age = cache_control[/max-age=(\d+)/, 1].to_i
    assert_operator max_age, :>, 0, "should still be cacheable"
    assert_operator max_age, :<=, 1.day.to_i, "a rules change must not take days to reach a crawler"
  end

  test "it names the sitemap" do
    get "/robots.txt"

    assert_match %r{^Sitemap: https?://\S+/sitemap\.xml$}, response.body
  end

  test "it disallows the ransack space in both spellings" do
    get "/robots.txt"

    assert_match(/Disallow: \/\*\?\*q%5B/, response.body)
    assert_match(/Disallow: \/\*&q%5B/, response.body)
    assert_match(/Disallow: \/\*\?\*q\[/, response.body)
  end

  test "it still blocks SemrushBot" do
    get "/robots.txt"

    assert_match(/User-agent: SemrushBot\nDisallow: \//, response.body)
  end

  test "no stale copy is left in public/ to shadow the route" do
    assert_not File.exist?(Rails.root.join("public/robots.txt")),
               "a file in public/ is served by middleware before the router ever runs"
  end
end
