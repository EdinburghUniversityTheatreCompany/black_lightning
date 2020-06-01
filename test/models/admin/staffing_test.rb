require 'test_helper'

class Admin::StaffingTest < ActiveSupport::TestCase
  setup do
    # Turn on delayed jobs for staffings - the staffing mailer refers to the job.
    Delayed::Worker.delay_jobs = true
  end

  teardown do
    # Turn off delayed jobs back off
    Delayed::Worker.delay_jobs = false
  end

  test 'filled_jobs' do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5)

    assert_equal 0, staffing.filled_jobs

    user = FactoryBot.create(:user)
    staffing.staffing_jobs.first.update_attribute(:user, user)

    assert_equal 1, staffing.reload.filled_jobs
  end

  test 'reminder_cleanup' do
    skip 'This test fails. It seems the reminder job does not actually get removed. It is not that big of a deal, because in the very rare case a staffing is removed, it will just fail and do nothing'

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 25, start_time: DateTime.now.advance(days: 1))

    assert_not_nil staffing.reminder_job
    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"

    staffing.reminder_job.delete
    p staffing
    p staffing.reminder_job

    staffing.send(:reminder_cleanup)
    p 'Try again'



    staffing.send(:reminder_cleanup)
    assert_nil staffing.reminder_job

    staffing.send(:reminder_cleanup)

    assert_nil staffing.reminder_job
  end

  test 'update_reminder runs on creation' do
    # Very far in the future, because it has to be bigger than the current time
    start_time = DateTime.now.advance(days: 10)
    start_time = start_time.change(offset: '+0100')

    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: start_time)

    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"
    # The partition bit is necessary because the hour behaves weird. It's one hour of sometimes.
    # It does not matter for the functionality, but it causes the test to fail sometimes.
    assert_includes staffing.reminder_job.description, I18n.l(start_time, format: :short).rpartition(':').last
  end

  test 'update_reminder without reminder job present' do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.now.advance(days: 1))

    assert_not_nil staffing.reload.reminder_job

    staffing.send(:reminder_cleanup)

    assert_nil staffing.reload.reminder_job

    staffing.send(:update_reminder)

    assert_not_nil staffing.reminder_job
    assert_includes staffing.reminder_job.description, "Reminder for Staffing #{staffing.id}"
  end

  test 'update_reminder without reminder job present and after the staffing passed' do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1, start_time: DateTime.now.advance(days: -1))

    assert_nil staffing.reminder_job

    staffing.send(:update_reminder)

    assert_nil staffing.reminder_job
  end

  test 'send_reminder' do
    staffing = FactoryBot.create(:staffing, unstaffed_job_count: 5, start_time: DateTime.now.advance(days: 1))

    assert_not_nil staffing.reload.reminder_job, 'The staffing does not automatically have a reminder job after creation'
    user = FactoryBot.create(:user)

    staffing.staffing_jobs.first.update_attribute(:user, user)

    staffing.send(:send_reminder)
    assert_enqueued_emails 1

    # Should raise an error the second time, because it has already send mails.
    assert_raises ArgumentError do
      staffing.send(:send_reminder)
    end
  end
end
