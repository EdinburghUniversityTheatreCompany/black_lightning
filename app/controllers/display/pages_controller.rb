# Pages for the box office Anthias screen. Public and unauthenticated -- every
# page shows what is already public elsewhere on the site.
class Display::PagesController < ApplicationController
  layout "display"
  skip_authorization_check

  before_action :set_display_headers

  def whats_on
    render_chain(Display::Panels::Identity.new)
  end

  def next_event
    render_chain(Display::Panels::Identity.new)
  end

  def credits
    render_chain(Display::Panels::Identity.new)
  end

  def get_involved
    render_chain(Display::Panels::Identity.new)
  end

  def news
    render_chain(Display::Panels::Identity.new)
  end

  def on_this_day
    render_chain(Display::Panels::Identity.new)
  end

  private

  def render_chain(*panels)
    @panel = Display::Chain.new(*panels).resolve
    render "panel"
  end

  def set_display_headers
    # Anthias must never hold a stale frame, and these pages have no business
    # in a search index.
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
