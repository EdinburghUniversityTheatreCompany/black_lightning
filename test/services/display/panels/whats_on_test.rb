require "test_helper"

class Display::Panels::WhatsOnTest < ActiveSupport::TestCase
  test "is unavailable when there is nothing upcoming" do
    Event.delete_all

    assert_not Display::Panels::WhatsOn.new.available?
  end

  test "is available and lists upcoming events when there are some" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)

    panel = Display::Panels::WhatsOn.new

    assert panel.available?
    assert_includes panel.locals[:events].map(&:id), show.id
  end

  test "caps the board at twelve rows" do
    Event.delete_all
    16.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    assert_equal Display::Panels::WhatsOn::ROWS, Display::Panels::WhatsOn.new.locals[:events].size
    assert_equal 12, Display::Panels::WhatsOn::ROWS
  end

  # A pass takes one fixed duration however long the board is, so the Anthias
  # slot is a constant too -- but the two are written down in different files
  # and a slot shorter than a pass would cut the scroll off before the bottom of
  # the list was ever on screen.
  test "the Anthias slot covers a full pass of the marquee" do
    slot = Display::SetupController.playlist.find { |e| e[:path] == "/display/whats-on" }
    css = Rails.root.join("app/javascript/entrypoints/display.css").read
    pass_seconds = css[/animation:\s*display-marquee\s+(\d+(?:\.\d+)?)s/, 1]

    assert pass_seconds, "could not find the marquee's duration in display.css"
    assert_operator slot[:seconds], :>=, pass_seconds.to_f,
                    "the playlist would cut the scroll off before the last event was shown"
  end
end
