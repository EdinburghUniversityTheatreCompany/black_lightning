class StaffingMailerPreview < ActionMailer::Preview
  def staffing_reminder
    StaffingMailer.staffing_reminder(staffed_job)
  end

  def calendar_invite_request
    StaffingMailer.calendar_invite(staffed_job)
  end

  def calendar_cancellation
    job = staffed_job

    StaffingMailer.calendar_cancellation(
      recipient: job.user,
      staffing: job.staffable,
      job_name: job.name,
      ics_data: job.ical_calendar(method: :cancel).to_ical
    )
  end

  private

  def staffed_job
    Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)
  end
end
