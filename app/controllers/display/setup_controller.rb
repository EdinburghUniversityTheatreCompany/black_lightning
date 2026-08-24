# Whoever sets up the Raspberry Pi copies the playlist off this page rather than
# out of a chat log or a commit message.
class Display::SetupController < ApplicationController
  skip_authorization_check

  # Durations in seconds. A poster wants dwelling on; a headline is read once.
  PLAYLIST = [
    { path: "/display/next/1", seconds: 20, note: "Tonight's show when one is running, else the next one" },
    { path: "/display/next/2", seconds: 20, note: "Second event in the pool" },
    { path: "/display/next/3", seconds: 20, note: "Third" },
    { path: "/display/next/4", seconds: 20, note: "Fourth" },
    { path: "/display/next/5", seconds: 20, note: "Fifth (repeats an earlier one if the pool is short)" },
    { path: "/display/next/6", seconds: 20, note: "Sixth (likewise)" },
    { path: "/display/whats-on", seconds: 18, note: "The upcoming schedule board" },
    { path: "/display/tonight-credits", seconds: 18, note: "Cast and company for tonight's show when one is running, else the next one" },
    { path: "/display/get-involved", seconds: 15, note: "Open opportunities" },
    { path: "/display/news", seconds: 12, note: "Latest news headline" },
    { path: "/display/on-this-day", seconds: 15, note: "Something from the archive" }
  ].freeze

  def show
    @playlist = PLAYLIST
  end
end
