require "test_helper"
require "fugit"

# RecurringEnqueueRetry catches a deadlocked enqueue, but not colliding is the actual fix and it
# costs nothing to keep.
class RecurringScheduleTest < ActiveSupport::TestCase
  SCHEDULES = YAML.load_file(Rails.root.join("config/recurring.yml")).freeze

  # reimbursements_mailbox_poll runs every 5 minutes, so it occupies every minute divisible by
  # five. A daily job landing on one of those collides with it every single day.
  DENSE_POLL_INTERVAL_MINUTES = 5

  def crons
    SCHEDULES.to_h { |key, config| [ key, Fugit.parse(config.fetch("schedule")) ] }
  end

  test "every schedule parses" do
    crons.each do |key, cron|
      assert_not_nil cron, "#{key} has an unparseable schedule"
    end
  end

  test "no two daily jobs are due at the same time" do
    times = daily_jobs.to_h { |key, cron| [ key, [ cron.hours, cron.minutes ] ] }

    collisions = times.group_by { |_, time| time }.select { |_, group| group.length > 1 }

    assert_empty collisions.transform_values { |group| group.map(&:first) },
                 "daily jobs due at the same minute deadlock each other in InnoDB"
  end

  test "no daily job lands on the five-minute mailbox poll grid" do
    offenders = daily_jobs.reject { |_, cron| (cron.minutes.first % DENSE_POLL_INTERVAL_MINUTES).nonzero? }

    assert_empty offenders.keys,
                 "a daily job on a minute divisible by #{DENSE_POLL_INTERVAL_MINUTES} races the " \
                 "every-5-minute mailbox poll every day"
  end

  # The one that actually broke: both were "at 3am every day" and roughly half the pretix runs
  # were dropped between 2026-08-27 and 2026-08-31.
  test "the pretix reconcile and the bank details retention no longer share a slot" do
    pretix = crons.fetch("pretix_reconcile_memberships")
    retention = crons.fetch("reimbursements_bank_details_retention")

    assert_not_equal [ pretix.hours, pretix.minutes ], [ retention.hours, retention.minutes ]
  end

  # Every 15 minutes, so it can collide every quarter hour rather than once a
  # day. climate_mailbox_poll already sits on :00/:15/:30/:45 -- the grid the
  # every-5-minute mailbox poll owns -- so this one is offset off it instead of
  # joining the pile.
  test "the pretix performance sync avoids the five-minute mailbox poll grid" do
    minutes = crons.fetch("pretix_sync_performances").minutes

    assert minutes.all? { |minute| (minute % DENSE_POLL_INTERVAL_MINUTES).nonzero? },
           "#{minutes.inspect} races the every-5-minute mailbox poll"
    assert_operator minutes.size, :>=, 4, "sold-out state is read from this job and goes stale fast"
  end

  private

  # Cron entries pinned to a specific hour and minute. The interval schedules ("every 5 minutes")
  # parse to a Fugit::Duration and have no fixed slot to collide on.
  def daily_jobs
    crons.select { |_, cron| cron.is_a?(Fugit::Cron) && cron.hours.present? && cron.minutes.present? }
  end
end
