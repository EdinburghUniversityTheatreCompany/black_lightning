# Whoever sets up the Raspberry Pi copies the playlist off this page rather than
# out of a chat log or a commit message.
class Display::SetupController < ApplicationController
  skip_authorization_check

  before_action { response.headers["X-Robots-Tag"] = "noindex, nofollow" }

  # Durations in seconds. Each entry names a route helper, not a path string, so a
  # renamed route fails here instead of leaving a Pi typed with dead URLs.
  PLAYLIST = [
    { route: [ :display_next_event_path, 1 ], seconds: 20, note: "Tonight's show when one is running, else the next one" },
    { route: [ :display_next_event_path, 2 ], seconds: 20, note: "Second event in the pool" },
    { route: [ :display_next_event_path, 3 ], seconds: 20, note: "Third" },
    { route: [ :display_next_event_path, 4 ], seconds: 20, note: "Fourth" },
    { route: [ :display_next_event_path, 5 ], seconds: 20, note: "Fifth (repeats an earlier one if the pool is short)" },
    { route: [ :display_next_event_path, 6 ], seconds: 20, note: "Sixth (likewise)" },
    # Must stay >= the marquee duration in display.css: a pass is paced to finish inside its slot.
    { route: [ :display_whats_on_path ], seconds: 18,
      note: "The upcoming schedule board (scrolls when there are more events than fit)" },
    { route: [ :display_credits_path ], seconds: 18, note: "Cast and company for tonight's show when one is running, else the next one" },
    { route: [ :display_get_involved_path ], seconds: 15, note: "Open opportunities" },
    { route: [ :display_news_path ], seconds: 12, note: "Latest news headline" },
    { route: [ :display_on_this_day_path ], seconds: 15, note: "Something from the archive -- a different show each time it comes round" }
  ].freeze

  # Lazy: route helpers are not callable while the controller is loading.
  def self.playlist
    helpers = Rails.application.routes.url_helpers

    PLAYLIST.map { |entry| entry.except(:route).merge(path: helpers.public_send(*entry[:route])) }
  end

  def show
    @playlist = self.class.playlist
  end
end
