# == Schema Information
#
# Table name: admin_staffings
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *start_time*::          <tt>datetime</tt>
# *show_title*::          <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *reminder_job_id*::     <tt>integer</tt>
# *end_time*::            <tt>datetime</tt>
# *counts_towards_debt*:: <tt>boolean</tt>
# *slug*::                <tt>string(255)</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::StaffingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  test "filled_jobs" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5)

    assert_equal 0, staffing.filled_jobs

    user = FactoryBot.create(:user)
    staffing.staffing_jobs.first.update_attribute(:user, user)

    assert_equal 1, staffing.reload.filled_jobs
  end

  test "update_reminder runs on creation" do
    # Very far in the future, because it has to be bigger than the current time
    start_time = DateTime.current.advance(days: 10)
    start_time = start_time.change(hour: 18, min: 0)

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: start_time)

    assert_equal false, staffing.reminder_job_executed, "Reminder job should not be executed yet"
  end

  test "update_reminder with past staffing does nothing" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: -1))

    original_executed_state = staffing.reminder_job_executed

    staffing.send(:update_reminder)

    assert_equal original_executed_state, staffing.reminder_job_executed, "Should not change executed state for past staffing"
  end

  test "send_reminder with ActiveJob" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5, start_time: DateTime.current.advance(days: 1))

    assert_equal false, staffing.reload.reminder_job_executed, "Reminder job should not be executed initially"
    user = FactoryBot.create(:user)

    staffing.staffing_jobs.first.update_attribute(:user, user)

    # Manually execute the job
    StaffingReminderJob.new.perform(staffing.id)

    assert staffing.reload.reminder_job_executed, "The reminder job should be marked as executed"

    # Should raise an error the second time, because it has already been executed.
    assert_raises ArgumentError do
      StaffingReminderJob.new.perform(staffing.id)
    end
  end
end
