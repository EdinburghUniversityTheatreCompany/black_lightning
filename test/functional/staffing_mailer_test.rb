require 'test_helper'

class StaffingMailerTest < ActionMailer::TestCase
  setup do
    #Turn on delayed jobs for staffings - the staffing mailer refers to the job.
    Delayed::Worker.delay_jobs = true
  end

  teardown do
    #Turn off delayed jobs back off
    Delayed::Worker.delay_jobs = false
  end

  test "should send staffing_reminder" do
    staffing = FactoryGirl.create(:staffing, job_count: 5)

    staffing.staffing_jobs.each do |job|
      if job.user then
        email = StaffingMailer.staffing_reminder(job).deliver
        assert !ActionMailer::Base.deliveries.empty?

        # Test the body of the sent email contains what we expect it to
        assert_equal [job.user.email], email.to
        assert_equal "Bedlam Theatre Staffing", email.subject
      else
        assert_nil StaffingMailer.staffing_reminder(job).deliver
        assert     ActionMailer::Base.deliveries.empty?
      end
      
      ActionMailer::Base.deliveries = []
    end
  end
end
