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
        assert_equal 'Bedlam Theatre Staffing', email.subject
      else
        assert_no_difference 'ActionMailer::Base.deliveries.count' do
          assert_nil StaffingMailer.staffing_reminder(job).deliver_now
        end
      end
    end
  end
end
