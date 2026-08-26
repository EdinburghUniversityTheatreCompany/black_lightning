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

  # The board scrolls its overflow past instead of truncating titles, so the
  # Anthias slot has to be long enough for a full pass -- otherwise the tail of
  # the list is never on screen at all.
  test "the Anthias slot is long enough for a full pass of a full board" do
    Event.delete_all
    Display::Panels::WhatsOn::ROWS.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    full_board = Display::Panels::WhatsOn.new.locals[:scroll_seconds]
    slot = Display::SetupController.playlist.find { |e| e[:path] == "/display/whats-on" }

    assert_equal full_board, Display::Panels::WhatsOn.max_scroll_seconds
    assert_operator slot[:seconds], :>=, full_board,
                    "the playlist would cut the scroll off before the last event was shown"
  end

  test "a shorter board takes proportionally less time to scroll" do
    Event.delete_all
    3.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    assert_operator Display::Panels::WhatsOn.new.locals[:scroll_seconds], :<,
                    Display::Panels::WhatsOn.max_scroll_seconds
  end
end
