require "test_helper"

class Display::Panels::NewsTest < ActiveSupport::TestCase
  test "is unavailable when there is no published news" do
    News.delete_all

    assert_not Display::Panels::News.new.available?
  end

  test "shows the most recently published public item" do
    News.delete_all
    FactoryBot.create(:news, show_public: true, publish_date: 3.days.ago, title: "Older")
    newest = FactoryBot.create(:news, show_public: true, publish_date: 1.day.ago, title: "Newest")

    panel = Display::Panels::News.new

    assert panel.available?
    assert_equal newest.id, panel.locals[:article].id
  end

  test "ignores private and future-dated items" do
    News.delete_all
    FactoryBot.create(:news, show_public: false, publish_date: 1.day.ago)
    FactoryBot.create(:news, show_public: true, publish_date: 3.days.from_now)

    assert_not Display::Panels::News.new.available?
  end
end
