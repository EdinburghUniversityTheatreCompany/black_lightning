class StaffingMailer < ApplicationMailer
  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user

    return if @user.nil?

    @subject = 'Bedlam Theatre Staffing'

    mail(to: @user.email, subject: @subject)
  end
end
