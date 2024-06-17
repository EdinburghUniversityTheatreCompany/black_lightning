require 'test_helper'

class StaffingMailerTest < ActionMailer::TestCase
  setup do
    # Turn on delayed jobs for staffings - the staffing mailer refers to the job.
    Delayed::Worker.delay_jobs = true
  end

  teardown do
    # Turn off delayed jobs back off
    Delayed::Worker.delay_jobs = false
  end

  test 'should send staffing_reminder' do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 3)

    staffing.staffing_jobs.each do |job|
      if job.user
        email = nil
        assert_difference 'ActionMailer::Base.deliveries.count' do
          email = StaffingMailer.staffing_reminder(job).deliver_now
        end

        # Test the body of the sent email contains what we expect it to
        assert_equal [job.user.email], email.to
        assert_includes email.subject, 'Bedlam Theatre Staffing'
      else
        assert_no_difference 'ActionMailer::Base.deliveries.count' do
          assert_nil StaffingMailer.staffing_reminder(job).deliver_now
        end
      end
    end
  end

  test 'should send staffing_reminder with a duty manager and committee rep' do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 3)
    staffing.staffing_jobs[0].update(name: 'duty manager', user: FactoryBot.create(:user))
    staffing.staffing_jobs[1].update(name: 'committee rep', user: FactoryBot.create(:user))

    job = staffing.staffing_jobs[2]
    email = StaffingMailer.staffing_reminder(job).deliver_now

    assert_includes email.body.encoded, 'Duty Manager'
    assert_includes email.body.encoded, 'Committee Rep'
  end

  test 'should send staffing_reminder with a duty manager' do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 3)
    staffing.staffing_jobs[0].update(name: 'duty manager', user: FactoryBot.create(:user))

    job = staffing.staffing_jobs[2]
    email = StaffingMailer.staffing_reminder(job).deliver_now

    assert_includes email.body.encoded, 'Duty Manager'
    refute_includes email.body.encoded, 'Committee Rep'
  end

  test 'should send staffing_reminder with a committee rep' do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 3)
    staffing.staffing_jobs[0].update(name: 'committee rep', user: FactoryBot.create(:user))

    job = staffing.staffing_jobs[2]
    email = StaffingMailer.staffing_reminder(job).deliver_now

    refute_includes email.body.encoded, 'Duty Manager'
    assert_includes email.body.encoded, 'Committee Rep'
  end

  test 'should send staffing_reminder without duty manager and committee rep' do
    staffing = FactoryBot.create(:staffing, staffed_job_count: 3)

    job = staffing.staffing_jobs[2]
    email = StaffingMailer.staffing_reminder(job).deliver_now

    refute_includes email.body.encoded, 'Duty Manager'
    refute_includes email.body.encoded, 'Committee Rep'
  end
end
