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

  test "every scheduled class exists and is a job" do
    SCHEDULES.each do |name, config|
      klass = config["class"].safe_constantize

      assert_not_nil klass, "#{name} names a class that does not exist: #{config['class']}"
      assert_operator klass, :<, ActiveJob::Base, "#{name} names #{klass}, which is not a job"
    end
  end

  test "every entry declares a queue and a schedule" do
    SCHEDULES.each do |name, config|
      assert config["queue"].present?, "#{name} has no queue"
      assert config["schedule"].present?, "#{name} has no schedule"
    end
  end

  # No indoor poller on purpose: crypt readings arrive by CSV import.
  test "the outdoor climate poller is scheduled" do
    assert_equal "Climate::OutdoorPollJob", SCHEDULES.dig("climate_outdoor_poll", "class")
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
  # parse to a Fugit::Duration and have no fixed slot to collide on.
  def daily_jobs
    crons.select { |_, cron| cron.is_a?(Fugit::Cron) && cron.hours.present? && cron.minutes.present? }
  end
end
