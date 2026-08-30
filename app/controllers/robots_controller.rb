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
    expires_in 1.hour, public: true

    render "robots/show", layout: false, content_type: "text/plain", formats: [ :text ]
  end
end
