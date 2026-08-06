require "test_helper"

# config/recurring.yml is read by Solid Queue at boot, so a typo in a class name
# or a renamed job surfaces as a job that silently never runs in production.
# Nothing else in the suite reads this file.
class RecurringScheduleTest < ActiveSupport::TestCase
  SCHEDULE = YAML.load_file(Rails.root.join("config/recurring.yml")).freeze

  test "every scheduled class exists and is a job" do
    SCHEDULE.each do |name, config|
      klass = config["class"].safe_constantize

      assert_not_nil klass, "#{name} names a class that does not exist: #{config['class']}"
      assert_operator klass, :<, ActiveJob::Base, "#{name} names #{klass}, which is not a job"
    end
  end

  test "every entry declares a queue and a schedule" do
    SCHEDULE.each do |name, config|
      assert config["queue"].present?, "#{name} has no queue"
      assert config["schedule"].present?, "#{name} has no schedule"
    end
  end

  test "the outdoor climate poller is scheduled" do
    # There is deliberately no indoor poller: crypt readings arrive by CSV
    # import, so nothing recurring feeds them.
    assert_equal "Climate::OutdoorPollJob", SCHEDULE.dig("climate_outdoor_poll", "class")
    assert_nil SCHEDULE["climate_sensor_poll"]
  end
end
