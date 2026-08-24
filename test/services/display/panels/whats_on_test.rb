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

  test "caps the board at eight rows" do
    Event.delete_all
    12.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    assert_equal 8, Display::Panels::WhatsOn.new.locals[:events].size
  end
end
