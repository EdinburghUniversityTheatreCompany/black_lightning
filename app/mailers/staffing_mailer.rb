class StaffingMailer < ApplicationMailer
  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user

    return if @user.nil?

    @start_time = l @staffing.start_time, format: :long
    @subject = "Bedlam Theatre Staffing at #{@start_time}"

    mail(to: @user.email, subject: @subject)
  end
end
