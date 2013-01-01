class StaffingMailer < ActionMailer::Base
  default from: "webserver@bedlamtheatre.co.uk"

  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user

    mail(:to => @user.email, :subject => "Bedlam Theatre Staffing")
  end
end
