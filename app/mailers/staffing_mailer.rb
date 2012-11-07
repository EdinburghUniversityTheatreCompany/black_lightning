class StaffingMailer < ActionMailer::Base
  default from: "webserver@bedlamtheatre.co.uk"

  def staffing_reminder(staffing)
    @staffing = staffing

    staffing.users.each do |user| 
      @user = user
      mail(:to => user.email, :subject => "Bedlam Theatre Staffing")
    end
  end
end
