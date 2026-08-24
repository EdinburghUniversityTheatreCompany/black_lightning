require "test_helper"

class Display::Panels::OnThisDayTest < ActiveSupport::TestCase
  setup do
    Event.delete_all
  end

  # A one-day run on today's month and day, N years back.
  def archive_show(years_ago:, attach_image: true, run_days: 0, is_public: true)
    start_date = Date.new(Date.current.year - years_ago, Date.current.month, Date.current.day)

    FactoryBot.create(:show, is_public: is_public, attach_image: attach_image,
                             start_date: start_date, end_date: start_date + run_days)
  end

  test "is unavailable when nothing matches" do
    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "finds an old show that ran on this day" do
    show = archive_show(years_ago: 12)

    panel = Display::Panels::OnThisDay.new

    assert panel.available?
    assert_equal show.id, panel.locals[:event].id
    assert_equal 12, panel.locals[:years_ago]
  end

  test "prefers the oldest match so the pick is deterministic" do
    oldest = archive_show(years_ago: 20)
    archive_show(years_ago: 5)

    assert_equal oldest.id, Display::Panels::OnThisDay.new.locals[:event].id
  end

  test "excludes anything that ended less than a year ago" do
    archive_show(years_ago: 0)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes a run longer than sixty days" do
    # A residency or a term-long season matches most of the calendar and is not
    # an "on this day" story.
    archive_show(years_ago: 8, run_days: 90)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes an event with no real artwork" do
    # fetch_image would attach a generated placeholder, so the guard has to be a
    # join on the attachment, checked before anything calls fetch_image.
    archive_show(years_ago: 8, attach_image: false)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes a private event" do
    archive_show(years_ago: 8, is_public: false)

    assert_not Display::Panels::OnThisDay.new.available?
  end
end
