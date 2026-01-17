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

  test "update_reminder runs on creation and sets scheduled_job_id" do
    # Very far in the future, because it has to be bigger than the current time
    start_time = DateTime.current.advance(days: 10)
    start_time = start_time.change(hour: 18, min: 0)

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: start_time)

    assert_equal false, staffing.reminder_job_executed, "Reminder job should not be executed yet"
    assert_not_nil staffing.scheduled_job_id, "Staffing should have a scheduled job ID"
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

    # Second execution should return silently (no error)
    assert_nothing_raised do
      StaffingReminderJob.new.perform(staffing.id)
    end
  end

  test "reminder job tracks individual recipients with reminder_sent_at" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 2, start_time: DateTime.current.advance(days: 1))
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    staffing.staffing_jobs.first.update!(user: user1)
    staffing.staffing_jobs.second.update!(user: user2)

    # All start with nil reminder_sent_at
    assert_nil staffing.staffing_jobs.first.reminder_sent_at
    assert_nil staffing.staffing_jobs.second.reminder_sent_at

    StaffingReminderJob.new.perform(staffing.id)

    # Both should now have reminder_sent_at set
    assert_not_nil staffing.staffing_jobs.first.reload.reminder_sent_at
    assert_not_nil staffing.staffing_jobs.second.reload.reminder_sent_at
    assert staffing.reload.reminder_job_executed
  end

  test "reminder_sent_at is reset when staffing is rescheduled" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: 1))
    user = FactoryBot.create(:user)
    staffing.staffing_jobs.first.update!(user: user)

    # Execute the job
    StaffingReminderJob.new.perform(staffing.id)
    assert_not_nil staffing.staffing_jobs.first.reload.reminder_sent_at

    # Update the staffing (triggers reschedule)
    staffing.update!(show_title: "Rescheduled Show")

    # reminder_sent_at should be reset
    assert_nil staffing.staffing_jobs.first.reload.reminder_sent_at
    assert_not staffing.reload.reminder_job_executed
  end

  test "scheduled job is properly managed when staffing is updated" do
    # Create a staffing with a future start time
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: 1))

    original_job_id = staffing.scheduled_job_id
    assert_not_nil original_job_id, "Should have a scheduled job ID"

    # Update the staffing (e.g., change show title) - should reschedule job
    staffing.update!(show_title: "Updated Show Title")

    new_job_id = staffing.reload.scheduled_job_id
    assert_not_nil new_job_id, "Should still have a scheduled job ID after update"
    assert_not_equal original_job_id, new_job_id, "Should have a new job ID after rescheduling"
    assert_not staffing.reminder_job_executed, "Job executed flag should be reset after rescheduling"

    # But if we update just the reminder_job_executed flag to true (like the job does), it should stay true
    staffing.update!(reminder_job_executed: true)
    assert staffing.reload.reminder_job_executed, "Flag should stay true when job marks itself as executed"
    assert_equal new_job_id, staffing.scheduled_job_id, "Job ID should not change when only marking as executed"
  end
end
