class StaffingMailer < ActionMailer::Base
  default from: "Bedlam Theatre <no-reply@bedlamtheatre.co.uk>"

  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user
    
    return if @user.nil?

    mail(:to => @user.email, :subject => "Bedlam Theatre Staffing")
  end
end
