# robots.txt, served by the app because `public_file_server.headers` would stamp a one-year
# cache-control on it from public/.
#
# Deliberately does NOT inherit ApplicationController:
#   * set_statement_timeout would need a live database, and a 5xx robots.txt stops Googlebot
#     crawling the whole site.
#   * the Devise filters touch the session, and a Set-Cookie response must not be publicly cacheable.
#   * require_profile_completion! would redirect a signed-in user with an incomplete profile.
class RobotsController < ActionController::Base
  def show
    # public: is safe only because nothing here touches the session. stale_if_error is a
    # mitigation: Cloudflare honours it only on Enterprise, and a dead Puma gives a 521/522 it
    # cannot serve stale for, so turn on Always Online (see the Deployment note in CLAUDE.md).
    expires_in 1.hour, public: true, stale_if_error: 1.day

    render "robots/show", layout: false, content_type: "text/plain", formats: [ :text ]
  end
end
