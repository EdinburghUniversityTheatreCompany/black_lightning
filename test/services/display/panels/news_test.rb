require "test_helper"

class Display::Panels::NewsTest < ActiveSupport::TestCase
  setup { ::News.delete_all }

  def headline(title, published_at = 1.day.ago)
    FactoryBot.create(:news, show_public: true, publish_date: published_at, title: title)
  end

  test "is unavailable when there is no published news" do
    assert_not Display::Panels::News.new.available?
  end

  test "lists the most recent published items, newest first" do
    older = headline("Older", 3.days.ago)
    newest = headline("Newest", 1.day.ago)

    panel = Display::Panels::News.new

    assert panel.available?
    assert_equal [ newest.id, older.id ], panel.locals[:articles].map(&:id)
  end

  test "ignores private and future-dated items" do
    headline("Private", 1.day.ago).update!(show_public: false)
    headline("Future", 3.days.from_now)

    assert_not Display::Panels::News.new.available?
  end

  # The slide is read from across a room in about twelve seconds, so the list is
  # bounded by the space it has rather than by a fixed count.
  test "fills to a line budget rather than a fixed number of headlines" do
    8.times { |i| headline("Short #{i}", (i + 1).days.ago) }

    listed = Display::Panels::News.new.locals[:articles]

    assert_operator listed.size, :<=, Display::Panels::News::MAX_ITEMS
    assert_operator listed.size, :>, 1, "short headlines should not be cut down to one"
  end

  test "a headline long enough to wrap crowds out the ones below it" do
    long = "EUTC Week 14 Newsletter - GM4, Rocky Horror Murder Mystery, " \
           "Turin/Bedlam Exchange Project \"Getting Naked For You\""
    # Distinct titles: News slugs from the title and must be unique.
    4.times { |i| headline("#{long} #{i}", (i + 1).days.ago) }

    listed = Display::Panels::News.new.locals[:articles]

    assert_operator listed.size, :<, 4, "wrapping headlines should yield fewer items, not overflow"
    assert_operator listed.size, :>=, 1, "at least the newest headline is always shown"
  end

  test "a single headline is always shown however long it is" do
    # 255 is the column's cap, so this is the longest headline that can exist.
    headline("A" * 250)

    assert_equal 1, Display::Panels::News.new.locals[:articles].size
  end
  # The budget is what keeps the QR code on screen, so it has to count each
  # item's date line as well as its headline.
  test "four one-line headlines fit, and a wrapping headline costs one of them" do
    4.times { |i| headline("Short headline #{i}", (i + 1).days.ago) }

    assert_equal 4, Display::Panels::News.new.locals[:articles].size

    ::News.delete_all
    headline("A" * 110, 1.day.ago)
    3.times { |i| headline("Short headline #{i}", (i + 2).days.ago) }

    assert_operator Display::Panels::News.new.locals[:articles].size, :<, 4
  end
end
