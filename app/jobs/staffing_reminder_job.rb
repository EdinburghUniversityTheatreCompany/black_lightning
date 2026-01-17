class StaffingReminderJob < ApplicationJob
  queue_as :reminders

  def perform(staffing_id)
    staffing = Admin::Staffing.find(staffing_id)

    if staffing.reminder_job_executed
      return
    end

    pending_jobs = staffing.staffing_jobs.where(reminder_sent_at: nil).where.not(user: nil)

    pending_jobs.each do |staffing_job|
      StaffingMailer.staffing_reminder(staffing_job).deliver_now
      staffing_job.update!(reminder_sent_at: Time.current)
    end

    staffing.update!(reminder_job_executed: true)
  end
end
