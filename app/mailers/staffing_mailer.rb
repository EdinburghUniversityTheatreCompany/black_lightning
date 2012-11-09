class StaffingMailer < ActionMailer::Base
  default from: "webserver@bedlamtheatre.co.uk"

  def staffing_reminder(staffing)
    @staffing = staffing

    staffing.staffing_jobs.each do |job|
      @user = job.user
      mail(:to => @user.email, :subject => "Bedlam Theatre Staffing")
    end
  end
end
