class StaffingMailer < ApplicationMailer
  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user

    return if @user.nil?

    mail(to: @user.email, subject: 'Bedlam Theatre Staffing')
  end
end
