require "test_helper"

class Display::Panels::OnThisDayTest < ActiveSupport::TestCase
  setup do
    Event.delete_all
    # The cursor is cache state and the process keeps its cache between tests:
    # without this, where the last test left it decides what this one sees.
    Rails.cache.clear
  end

  # A short run over today's month and day, N years back. Two days rather than
  # one because on 29 February the start slips back to the 28th, and a one-day
  # run there would not cover today at all.
  def archive_show(years_ago:, attach_image: true, run_days: 2, is_public: true)
    start_date = Date.current - years_ago.years

    FactoryBot.create(:show, is_public: is_public, attach_image: attach_image,
                             start_date: start_date, end_date: start_date + run_days)
  end

  # A fresh panel per call: a new fetch of the URL is what rotates the pick.
  def rendered_event_id
    Display::Panels::OnThisDay.new.locals[:event].id
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

  test "the first render of the day is the oldest match" do
    oldest = archive_show(years_ago: 20)
    archive_show(years_ago: 5)

    assert_equal oldest.id, rendered_event_id
  end

  # The screen comes back to this URL every few minutes, all day.
  test "each render shows a different match" do
    archive_show(years_ago: 20)
    archive_show(years_ago: 12)
    archive_show(years_ago: 5)

    assert_equal 3, 3.times.map { rendered_event_id }.uniq.size
  end

  test "the rotation walks every match in turn and then starts again" do
    oldest = archive_show(years_ago: 20)
    middle = archive_show(years_ago: 12)
    newest = archive_show(years_ago: 5)

    assert_equal [ oldest.id, middle.id, newest.id, oldest.id ],
                 4.times.map { rendered_event_id }
  end

  test "one match is shown every time rather than nothing on the second render" do
    show = archive_show(years_ago: 12)

    assert_equal [ show.id, show.id ], 2.times.map { rendered_event_id }
  end

  test "a single render answers with one event however often it is asked" do
    archive_show(years_ago: 20)
    archive_show(years_ago: 5)

    panel = Display::Panels::OnThisDay.new

    assert panel.available?
    assert_equal panel.locals[:event].id, panel.locals[:event].id
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

  test "excludes an event whose only artwork is a generated placeholder" do
    # fetch_image *attaches* the placeholder, so any archive page anyone has
    # ever opened carries an attachment. Asking only whether one exists answers
    # "has this been looked at", not "has a poster".
    show = archive_show(years_ago: 8, attach_image: false)
    show.fetch_image

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "a real upload still counts once a placeholder exists for another event" do
    archive_show(years_ago: 8, attach_image: false).fetch_image
    uploaded = archive_show(years_ago: 9)

    assert_equal [ uploaded.id ], 2.times.map { rendered_event_id }.uniq
  end

  test "excludes a private event" do
    archive_show(years_ago: 8, is_public: false)

    assert_not Display::Panels::OnThisDay.new.available?
  end
end
