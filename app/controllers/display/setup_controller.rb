# Whoever sets up the Raspberry Pi copies the playlist off this page rather than
# out of a chat log or a commit message.
class Display::SetupController < ApplicationController
  skip_authorization_check

  before_action { response.headers["X-Robots-Tag"] = "noindex, nofollow" }

  # Durations in seconds. A poster wants dwelling on; a headline is read once.
  #
  # Each entry names a route helper rather than a path string: a volunteer types
  # these URLs into a Pi, so a renamed route must not leave this page silently
  # listing dead ones.
  PLAYLIST = [
    { route: [ :display_next_event_path, 1 ], seconds: 20, note: "Tonight's show when one is running, else the next one" },
    { route: [ :display_next_event_path, 2 ], seconds: 20, note: "Second event in the pool" },
    { route: [ :display_next_event_path, 3 ], seconds: 20, note: "Third" },
    { route: [ :display_next_event_path, 4 ], seconds: 20, note: "Fourth" },
    { route: [ :display_next_event_path, 5 ], seconds: 20, note: "Fifth (repeats an earlier one if the pool is short)" },
    { route: [ :display_next_event_path, 6 ], seconds: 20, note: "Sixth (likewise)" },
    { route: [ :display_whats_on_path ], seconds: 18, note: "The upcoming schedule board" },
    { route: [ :display_credits_path ], seconds: 18, note: "Cast and company for tonight's show when one is running, else the next one" },
    { route: [ :display_get_involved_path ], seconds: 15, note: "Open opportunities" },
    { route: [ :display_news_path ], seconds: 12, note: "Latest news headline" },
    { route: [ :display_on_this_day_path ], seconds: 15, note: "Something from the archive -- a different show each time it comes round" }
  ].freeze

  # Resolved lazily, not at class-load: route helpers are not guaranteed to be
  # callable while the controller is being loaded.
  def self.playlist
    helpers = Rails.application.routes.url_helpers

    PLAYLIST.map { |entry| entry.except(:route).merge(path: helpers.public_send(*entry[:route])) }
  end

  def show
    @playlist = self.class.playlist
  end
end
