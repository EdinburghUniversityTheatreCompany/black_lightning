require "test_helper"

# Served by the app, not public/, so a rules change reaches crawlers instead of sitting behind a
# year-long cache-control.
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

  # A publicly cacheable response must not carry a session cookie: a shared cache would hand one
  # visitor's session to the next.
  test "it sets no session cookie, so public caching is safe" do
    get "/robots.txt"

    assert_includes response.headers["Cache-Control"].to_s, "public"
    # rack-mini-profiler sets its own cookie in dev and test; only the session one is the hazard.
    assert_not_includes response.headers["Set-Cookie"].to_s, "_chaos_rails_session",
                        "a publicly cached response must not carry a session cookie"
  end

  test "it is signed out of the application filter chain entirely" do
    assert_not RobotsController.ancestors.include?(ApplicationController),
               "inheriting ApplicationController makes robots.txt need the database, a session " \
               "and a complete profile -- and a 5xx robots.txt stops Googlebot crawling the site"
  end

  test "it answers with a session already established" do
    get new_user_session_path

    get "/robots.txt"

    assert_response :success
    assert_match(/Sitemap:/, response.body)
  end

  # Every image (og:image, JSON-LD) is served under /rails/, so a bare Disallow would bar it all.
  test "it does not block the ActiveStorage paths every image is served from" do
    get "/robots.txt"

    assert_match(%r{^Allow: /rails/active_storage/$}, response.body,
                 "images live under /rails/; the Allow must override the Disallow")

    disallow = response.body.index("Disallow: /rails/")
    allow = response.body.index("Allow: /rails/active_storage/")
    assert disallow && allow, "both rules should be present"
  end

  # A 5xx robots.txt stops Googlebot crawling the site, so the edge may serve a stale copy.
  test "the edge may serve a stale copy while the app is down" do
    get "/robots.txt"

    assert_includes response.headers["Cache-Control"].to_s, "stale-if-error=#{1.day.to_i}"
  end
end
