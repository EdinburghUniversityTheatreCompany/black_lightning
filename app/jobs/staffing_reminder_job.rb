class StaffingReminderJob < ApplicationJob
  queue_as :reminders

  def perform(staffing_id)
    staffing = Admin::Staffing.find(staffing_id)

    # Prevent the job from running more than once to prevent us spewing emails if there is an error.
    if staffing.reminder_job_executed
      Rails.logger.warn "StaffingReminderJob: Attempt to execute already completed reminder for staffing #{staffing_id} (#{staffing.show_title})"
      raise ArgumentError, "This reminder job has already been executed."
    end

    errors = []

    staffing.staffing_jobs.each do |job|
      # Keep going to other users if sending to one fails for some reason.
      next if job.user.nil?

      begin
        StaffingMailer.staffing_reminder(job).deliver_now
      rescue => e
        exception = e.exception "Error sending reminder to #{job.user.full_name} (ID: #{job.user.id}): " + e.message
        errors << exception
      end
    end

    # Mark as executed
    staffing.update!(reminder_job_executed: true)

    # Raise the errors now for the logs.
    errors&.each do |e|
      raise e
    end
  end
end
