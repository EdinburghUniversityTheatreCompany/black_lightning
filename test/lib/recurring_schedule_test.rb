require "test_helper"
require "fugit"

# config/recurring.yml is read by Solid Queue at boot, so a typo in a class name or a renamed
# job is a job that silently never runs in production. Not colliding is the fix for a
# deadlocked enqueue; RecurringEnqueueRetry is only the net.
class RecurringScheduleTest < ActiveSupport::TestCase
  SCHEDULES = YAML.load_file(Rails.root.join("config/recurring.yml")).freeze

  # reimbursements_mailbox_poll runs every 5 minutes, so a daily job on a minute divisible by
  # five collides with it every day.
  DENSE_POLL_INTERVAL_MINUTES = 5

  def crons
    SCHEDULES.to_h { |key, config| [ key, Fugit.parse(config.fetch("schedule")) ] }
  end

  test "every entry names a job, declares a queue and has a schedule that parses" do
    parsed = crons
    SCHEDULES.each do |name, config|
      klass = config["class"].to_s.safe_constantize

      assert klass && klass < ActiveJob::Base, "#{name} names #{config['class'].inspect}, which is not a job"
      assert config["queue"].present?, "#{name} has no queue"
      # Not covered by the parse below: Fugit reads a blank string as a zero Duration.
      assert config["schedule"].present?, "#{name} has no schedule"
      assert_not_nil parsed[name], "#{name} has an unparseable schedule"
    end
  end

  # No indoor poller on purpose: crypt readings arrive by CSV import.
  test "the outdoor climate poller is scheduled" do
    assert_equal "Climate::OutdoorPollJob", SCHEDULES.dig("climate_outdoor_poll", "class")
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

  # Every 15 minutes, so it could collide every quarter hour. It is offset off the
  # five-minute grid, which climate_mailbox_poll already shares.
  test "the pretix performance sync avoids the five-minute mailbox poll grid" do
    minutes = crons.fetch("pretix_sync_performances").minutes

    assert minutes.all? { |minute| (minute % DENSE_POLL_INTERVAL_MINUTES).nonzero? },
           "#{minutes.inspect} races the every-5-minute mailbox poll"
    assert_operator minutes.size, :>=, 4, "sold-out state is read from this job and goes stale fast"
  end

  private

  # Cron entries pinned to a specific hour and minute. The interval schedules ("every 5 minutes")
  # parse to a Fugit::Cron too, but with no hours, so the `hours.present?` test is what leaves
  # them out: they have no fixed slot to collide on.
  def daily_jobs
    crons.select { |_, cron| cron.is_a?(Fugit::Cron) && cron.hours.present? && cron.minutes.present? }
  end
end
