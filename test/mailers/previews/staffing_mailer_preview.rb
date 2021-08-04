class StaffingMailerPreview < ActionMailer::Preview
  def staffing_reminder
    job = Admin::StaffingJob.where.not(user: nil).sample || FactoryBot.create(:staffed_staffing_job)

    StaffingMailer.staffing_reminder(job)
  end
end
