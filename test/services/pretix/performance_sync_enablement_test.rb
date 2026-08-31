require "test_helper"

##
# Turning the sync on across a season's worth of shows.
#
# It deliberately does NOT ask pretix first: an event with no ticket shop yet
# waits and says so on its admin page, and a producer's hand-typed dates are
# adopted by the matching subevents rather than duplicated. See
# Pretix::PerformanceSyncTest for both.
##
class Pretix::PerformanceSyncEnablementTest < ActiveSupport::TestCase
  def future_show(slug:, **attributes)
    FactoryBot.create(:show, slug: slug, start_date: Date.current + 10, end_date: Date.current + 14,
                             **attributes)
  end

  def enable(apply: true)
    Pretix::PerformanceSyncEnablement.new.call(apply: apply)
  end

  test "a future event is switched on" do
    show = future_show(slug: "hamlet")

    summary = enable

    assert_equal [ "hamlet" ], summary.enabled.map(&:slug)
    assert_predicate show.reload, :pretix_sync_performances?
  end

  test "an event with no ticket shop yet is still switched on, and waits" do
    # The whole point of dropping the probe: the producer ticks it now and builds
    # the shop later, and the sync picks it up the moment the series appears.
    show = future_show(slug: "not-in-pretix-yet")

    assert_equal [ "not-in-pretix-yet" ], enable.enabled.map(&:slug)
    assert_predicate show.reload, :pretix_sync_performances?
  end

  test "a past run is left alone" do
    show = FactoryBot.create(:show, slug: "last-year", start_date: 1.year.ago.to_date,
                                    end_date: 1.year.ago.to_date + 3)

    assert_empty enable.enabled
    assert_not_predicate show.reload, :pretix_sync_performances?
  end

  # A Season's occurrences are opening times, not performances -- filling them
  # from ticketed dates would claim a show for every day the box office is open.
  test "a season is skipped" do
    season = FactoryBot.create(:season, slug: "fringe-2026", start_date: Date.current + 10,
                                        end_date: Date.current + 14)

    assert_equal [ "fringe-2026" ], enable.not_performances.map(&:slug)
    assert_not_predicate season.reload, :pretix_sync_performances?
  end

  test "an event already switched on is reported, not re-saved" do
    future_show(slug: "already", pretix_sync_performances: true)

    summary = enable

    assert_equal [ "already" ], summary.already_on.map(&:slug)
    assert_empty summary.enabled
  end

  test "a dry run reports what it would do and writes nothing" do
    show = future_show(slug: "hamlet")

    assert_equal [ "hamlet" ], enable(apply: false).enabled.map(&:slug)
    assert_not_predicate show.reload, :pretix_sync_performances?
  end
end
