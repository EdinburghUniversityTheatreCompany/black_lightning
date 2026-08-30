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

  # A response marked publicly cacheable must never carry a session cookie: a shared cache
  # (Cloudflare, in front of this site) would hand one visitor's session to the next.
  test "it sets no session cookie, so public caching is safe" do
    get "/robots.txt"

    assert_includes response.headers["Cache-Control"].to_s, "public"
    # rack-mini-profiler sets its own cookie in dev and test; the hazard is the session one.
    assert_not_includes response.headers["Set-Cookie"].to_s, "_chaos_rails_session",
                        "a publicly cached response must not carry a session cookie"
  end

  test "it is signed out of the application filter chain entirely" do
    assert_not RobotsController.ancestors.include?(ApplicationController),
               "inheriting ApplicationController makes robots.txt need the database, a session " \
               "and a complete profile -- and a 5xx robots.txt stops Googlebot crawling the site"
  end

  # require_profile_completion! redirects a signed-in user with an incomplete profile everywhere
  # else in the app; robots.txt must answer regardless of who is asking.
  test "it answers with a session already established" do
    get new_user_session_path

    get "/robots.txt"

    assert_response :success
    assert_match(/Sitemap:/, response.body)
  end
end
