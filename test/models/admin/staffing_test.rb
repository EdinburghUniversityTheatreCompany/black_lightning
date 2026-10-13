# == Schema Information
#
# Table name: admin_staffings
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *start_time*::          <tt>datetime</tt>
# *show_title*::          <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *end_time*::            <tt>datetime</tt>
# *counts_towards_debt*:: <tt>boolean</tt>
# *slug*::                <tt>string(255)</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::StaffingTest < ActiveSupport::TestCase
  test "filled_jobs" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5)

    assert_equal 0, staffing.filled_jobs

    user = FactoryBot.create(:user)
    staffing.staffing_jobs.first.update_attribute(:user, user)

    assert_equal 1, staffing.reload.filled_jobs
  end

  test "update_reminder with past staffing does nothing" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: -1))

    original_executed_state = staffing.reminder_job_executed

    staffing.send(:update_reminder)

    assert_equal original_executed_state, staffing.reminder_job_executed
  end

  test "reminder job tracks individual recipients with reminder_sent_at" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 2, start_time: DateTime.current.advance(days: 1))
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    staffing.staffing_jobs.first.update!(user: user1)
    staffing.staffing_jobs.second.update!(user: user2)

    StaffingReminderJob.new.perform(staffing.id)

    assert_not_nil staffing.staffing_jobs.first.reload.reminder_sent_at
    assert_not_nil staffing.staffing_jobs.second.reload.reminder_sent_at
    assert staffing.reload.reminder_job_executed

    # A second run returns early.
    assert_nothing_raised { StaffingReminderJob.new.perform(staffing.id) }
  end

  test "reminder_sent_at is reset when staffing is rescheduled" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: 1))
    user = FactoryBot.create(:user)
    staffing.staffing_jobs.first.update!(user: user)

    StaffingReminderJob.new.perform(staffing.id)
    assert_not_nil staffing.staffing_jobs.first.reload.reminder_sent_at

    staffing.update!(show_title: "Rescheduled Show")

    assert_nil staffing.staffing_jobs.first.reload.reminder_sent_at
    assert_not staffing.reload.reminder_job_executed
  end

  ##
  # Calendar invite cascade
  ##
  test "sends calendar updates to all assigned users when the title or times change" do
    [ ->(_) { { show_title: "New Show Title" } },
      ->(s) { { start_time: s.start_time.advance(hours: 1), end_time: s.end_time.advance(hours: 1) } },
      ->(s) { { end_time: s.end_time.advance(minutes: 30) } } ].each do |change|
      staffing = FactoryBot.create(:staffing, staffed_job_count: 2, unstaffed_job_count: 1)

      assert_enqueued_emails(2) { staffing.update!(change.(staffing)) }
    end
  end

  test "does not send calendar emails when only counts_towards_debt changes" do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 1, counts_towards_debt: false)

    assert_enqueued_emails(0) do
      staffing.update!(counts_towards_debt: true)
    end
  end

  test "scheduled job is properly managed when staffing is updated" do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.current.advance(days: 1))

    original_job_id = staffing.scheduled_job_id
    assert_not_nil original_job_id
    assert_not staffing.reminder_job_executed

    staffing.update!(show_title: "Updated Show Title")

    new_job_id = staffing.reload.scheduled_job_id
    assert_not_nil new_job_id
    assert_not_equal original_job_id, new_job_id
    assert_not staffing.reminder_job_executed, "Job executed flag should be reset after rescheduling"

    # The job marking itself executed must not reschedule.
    staffing.update!(reminder_job_executed: true)
    assert staffing.reload.reminder_job_executed, "Flag should stay true when job marks itself as executed"
    assert_equal new_job_id, staffing.scheduled_job_id
  end
end
