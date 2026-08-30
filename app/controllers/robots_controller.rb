##
# robots.txt, served by the app rather than from public/.
#
# It lived in public/, where `config.public_file_server.headers` stamps everything with a
# one-year cache-control -- correct for fingerprinted Vite assets, wrong for a stable URL whose
# contents change. Cloudflare honoured it: a rules change deployed on 2026-08-30 was still being
# served from a 30-day-old cached copy, and would have been for another eleven months.
##
class RobotsController < ApplicationController
  skip_authorization_check

  def show
    # Long enough that this is not a per-crawl origin hit, short enough that a rules change is
    # live the same day.
    expires_in 1.hour, public: true

    render layout: false, content_type: "text/plain"
  end
end
