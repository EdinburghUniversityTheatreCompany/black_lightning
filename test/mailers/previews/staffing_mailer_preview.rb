class StaffingMailerPreview < ActionMailer::Preview
  def staffing_reminder
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.staffing_reminder(job)
  end

  def calendar_invite_request
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.calendar_invite(job, method: :request)
  end

  def calendar_cancellation
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.calendar_cancellation(
      recipient: job.user,
      staffing: job.staffable,
      job_name: job.name,
      ics_data: job.ical_calendar(method: :cancel).to_ical
    )
  end
end
