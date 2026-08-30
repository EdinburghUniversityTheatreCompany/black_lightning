##
# robots.txt, served by the app rather than from public/, where
# `config.public_file_server.headers` stamps a one-year cache-control -- correct for
# fingerprinted Vite assets, wrong for a stable URL whose contents change.
#
# It deliberately does NOT inherit ApplicationController. That would give it the app's whole
# filter chain, and each part of it is a liability here:
#
#   * set_statement_timeout would make robots.txt need a live database. A 5xx robots.txt makes
#     Googlebot stop crawling the entire site, so this has to keep answering through an outage.
#   * the Devise/current_user filters touch the session, which sets a cookie -- and a response
#     carrying Set-Cookie must never be marked publicly cacheable.
#   * require_profile_completion! would redirect a signed-in user with an incomplete profile.
#
# The template holds no ERB expressions, so rendering it reads nothing.
##
class RobotsController < ActionController::Base
  def show
    # Long enough not to be a per-crawl origin hit, short enough that a rules change is live the
    # same day. public: is safe only because nothing above touches the session.
    #
    # stale_if_error asks a shared cache to keep serving the day-old copy rather than pass on an
    # error. It is a mitigation, not a guarantee: Cloudflare honours the directive only on
    # Enterprise, and a dead Puma surfaces as a connection-level 521/522 that serve-stale does not
    # apply to at all. Cloudflare's Always Online is what actually covers that case -- see the
    # Deployment note in CLAUDE.md. Worth sending regardless, since it costs nothing and other
    # caches do honour it.
    expires_in 1.hour, public: true, stale_if_error: 1.day

    render "robots/show", layout: false, content_type: "text/plain", formats: [ :text ]
  end
end
