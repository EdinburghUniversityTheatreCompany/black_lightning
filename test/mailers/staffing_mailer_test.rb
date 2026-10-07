require "test_helper"

class StaffingMailerTest < ActionMailer::TestCase
  test "calendar_invite emails the assigned user an ics REQUEST for the job" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)
    # Unfold RFC 5545 line continuations (CRLF+space or LF+space) before asserting
    ics = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s.gsub(/\r?\n[ \t]/, "")

    assert_equal [ job.user.email ], email.to
    assert_includes ics, "METHOD:REQUEST"
    assert_includes ics, "staffing-job-#{job.id}@bedlamtheatre.co.uk"
    assert_includes ics, job.staffable.show_title
    assert_includes ics, job.name
    assert_includes ics, job.staffable.start_time.utc.strftime("%Y%m%dT%H%M%SZ")
    assert_includes ics, job.staffable.end_time.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  test "calendar_invite sends to calendar_email override when set" do
    job = FactoryBot.create(:staffed_staffing_job)
    job.user.update!(calendar_email: "override@example.com")

    email = StaffingMailer.calendar_invite(job, method: :request)

    assert_equal [ "override@example.com" ], email.to
  end

  test "calendar_invite does not raise when job has no user" do
    job = FactoryBot.create(:staffing_job) # unassigned, user_id is nil

    assert_no_emails do
      StaffingMailer.calendar_invite(job, method: :request).deliver_now
    end
  end

  test "calendar_cancellation sends cancellation email without needing the job record" do
    job = FactoryBot.create(:staffed_staffing_job)
    recipient = job.user
    staffing = job.staffable
    job_name = job.name
    ics_data = job.ical_calendar(method: :cancel).to_ical

    email = StaffingMailer.calendar_cancellation(
      recipient: recipient,
      staffing: staffing,
      job_name: job_name,
      ics_data: ics_data
    )

    assert_equal [ recipient.email ], email.to
    assert_includes email.subject, "Staffing removed"
    ics_attachment = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }
    assert_not_nil ics_attachment, "Expected a text/calendar attachment"
    assert_includes ics_attachment.body.to_s, "METHOD:CANCEL"
    assert_includes ics_attachment.body.to_s, "staffing-job-#{job.id}@bedlamtheatre.co.uk"
  end

  test "calendar_cancellation does not raise when recipient is nil" do
    job = FactoryBot.create(:staffed_staffing_job)
    ics_data = job.ical_calendar(method: :cancel).to_ical

    assert_no_emails do
      StaffingMailer.calendar_cancellation(
        recipient: nil,
        staffing: job.staffable,
        job_name: job.name,
        ics_data: ics_data
      ).deliver_now
    end
  end

  test "destroying a staffing job with a user enqueues a calendar_cancellation email" do
    job = FactoryBot.create(:staffed_staffing_job)

    assert_enqueued_emails(1) do
      job.destroy
    end

    job_data = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    assert_equal "StaffingMailer", job_data["arguments"].first
    assert_equal "calendar_cancellation", job_data["arguments"].second
  end

  test "destroying a staffing job without a user does not enqueue a cancellation email" do
    job = FactoryBot.create(:unstaffed_staffing_job)

    assert_no_enqueued_emails do
      job.destroy
    end
  end
end
