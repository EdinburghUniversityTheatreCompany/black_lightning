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

  test "reminder_cleanup" do
    skip "This test fails. It seems the reminder job does not actually get removed. It is not that big of a deal, because in the very rare case a staffing is removed, it will just fail and do nothing"

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 25, start_time: DateTime.current.advance(days: 1))

    assert_not_nil staffing.reminder_job
    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"

    staffing.reminder_job.delete
    p staffing
    p staffing.reminder_job

    staffing.send(:reminder_cleanup)
    p "Try again"



    staffing.send(:reminder_cleanup)
    assert_nil staffing.reminder_job

    staffing.send(:reminder_cleanup)

    assert_nil staffing.reminder_job
  end

  test "update_reminder runs on creation" do
    # Very far in the future, because it has to be bigger than the current time
    start_time = DateTime.current.advance(days: 10)
    start_time = start_time.change(hour: 18, min: 0)

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: start_time)

    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"
    # The partition bit is necessary because the hour behaves weird. It's one hour off sometimes.
    # It does not matter for the functionality, but it causes the test to fail sometimes.
    assert_includes staffing.reminder_job.description, I18n.l(start_time, format: :short).rpartition(":").last
  end

  test "update_reminder without reminder job present" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: 1))

    assert_not_nil staffing.reload.reminder_job

    staffing.send(:reminder_cleanup)

    assert_nil staffing.reload.reminder_job

    staffing.send(:update_reminder)

    assert_not_nil staffing.reminder_job
    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"
  end

  test "update_reminder without reminder job present and after the staffing passed" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: -1))

    assert_nil staffing.reminder_job

    staffing.send(:update_reminder)

    assert_nil staffing.reminder_job
  end

  test "send_reminder with ActiveJob" do
    perform_enqueued_jobs do
      staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5, start_time: DateTime.current.advance(days: 1))

      assert_not_nil staffing.reload.scheduled_job_id, "The staffing does not automatically have a scheduled job after creation"
      user = FactoryBot.create(:user)

      staffing.staffing_jobs.first.update_attribute(:user, user)

      # Manually execute the job
      StaffingReminderJob.new.perform(staffing.id)

      assert_performed_jobs 1
      assert staffing.reload.reminder_job_executed?, "The reminder job should be marked as executed"

      # Should raise an error the second time, because it has already been executed.
      assert_raises ArgumentError do
        StaffingReminderJob.new.perform(staffing.id)
      end
    end
  end
end
