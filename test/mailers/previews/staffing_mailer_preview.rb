class StaffingMailerPreview < ActionMailer::Preview
  def staffing_reminder
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.staffing_reminder(job)
  end

  def calendar_invite_request
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.calendar_invite(job, method: :request)
  end

  def calendar_invite_cancel
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.calendar_invite(job, method: :cancel)
  end
end
