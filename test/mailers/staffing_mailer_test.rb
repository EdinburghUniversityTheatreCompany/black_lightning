require "test_helper"

class StaffingMailerTest < ActionMailer::TestCase
  test "calendar_invite sends email to the assigned user" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)

    assert_equal [ job.user.email ], email.to
  end

  test "calendar_invite REQUEST has a text/calendar attachment" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)
    ics_attachment = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }

    assert_not_nil ics_attachment, "Expected a text/calendar attachment"
  end

  test "calendar_invite REQUEST ics contains METHOD:REQUEST" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)
    ics = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s

    assert_includes ics, "METHOD:REQUEST"
  end

  test "calendar_invite REQUEST ics has stable UID based on job id" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)
    ics = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s

    assert_includes ics, "staffing-job-#{job.id}@bedlamtheatre.co.uk"
  end

  test "calendar_invite REQUEST ics summary contains show title and role" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :request)
    ics_raw = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s
    # Unfold RFC 5545 line continuations (CRLF+space or LF+space) before asserting
    ics = ics_raw.gsub(/\r?\n[ \t]/, "")

    assert_includes ics, job.staffable.show_title
    assert_includes ics, job.name
  end

  test "calendar_invite REQUEST ics has correct start and end times" do
    job = FactoryBot.create(:staffed_staffing_job)
    expected_start = job.staffable.start_time.utc.strftime("%Y%m%dT%H%M%SZ")
    expected_end   = job.staffable.end_time.utc.strftime("%Y%m%dT%H%M%SZ")

    email = StaffingMailer.calendar_invite(job, method: :request)
    ics = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s

    assert_includes ics, expected_start
    assert_includes ics, expected_end
  end

  test "calendar_invite CANCEL ics contains METHOD:CANCEL" do
    job = FactoryBot.create(:staffed_staffing_job)

    email = StaffingMailer.calendar_invite(job, method: :cancel)
    ics = email.attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s

    assert_includes ics, "METHOD:CANCEL"
  end

  test "calendar_invite sends to calendar_email override when set" do
    job = FactoryBot.create(:staffed_staffing_job)
    job.user.update!(calendar_email: "override@example.com")

    email = StaffingMailer.calendar_invite(job, method: :request)

    assert_equal [ "override@example.com" ], email.to
  end

  test "calendar_invite CANCEL uses same UID as REQUEST for the same job" do
    job = FactoryBot.create(:staffed_staffing_job)

    request_ics = StaffingMailer.calendar_invite(job, method: :request).attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s
    cancel_ics  = StaffingMailer.calendar_invite(job, method: :cancel).attachments.find { |a| a.mime_type.start_with?("text/calendar") }.body.to_s

    uid = "staffing-job-#{job.id}@bedlamtheatre.co.uk"
    assert_includes request_ics, uid
    assert_includes cancel_ics, uid
  end
end
