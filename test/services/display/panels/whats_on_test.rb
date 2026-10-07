require "test_helper"

class Display::Panels::WhatsOnTest < ActiveSupport::TestCase
  test "caps the board at twelve rows" do
    Event.delete_all
    16.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    assert_equal Display::Panels::WhatsOn::ROWS, Display::Panels::WhatsOn.new.locals[:events].size
  end

  # The slot and the marquee pass live in different files; a short slot cuts the
  # scroll off before the bottom of the list is shown.
  test "the Anthias slot covers a full pass of the marquee" do
    slot = Display::SetupController.playlist.find { |e| e[:path] == "/display/whats-on" }
    css = Rails.root.join("app/javascript/entrypoints/display.css").read
    pass_seconds = css[/animation:\s*display-marquee\s+(\d+(?:\.\d+)?)s/, 1]

    assert pass_seconds, "could not find the marquee's duration in display.css"
    assert_operator slot[:seconds], :>=, pass_seconds.to_f,
                    "the playlist would cut the scroll off before the last event was shown"
  end
end
