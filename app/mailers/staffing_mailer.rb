class StaffingMailer < ActionMailer::Base
  default from: "webserver@bedlamtheatre.co.uk"

  def staffing_reminder(staffing)
    @staffing = staffing
# set up a client to talk to the Twilio REST API
    client = ::Twilio::REST::Client.new ChaosRails::Application.config.twilio_account_sid, ChaosRails::Application.config.twilio_auth_token

    staffing.staffing_jobs.each do |job|
      @user = job.user
      mail(:to => @user.email, :subject => "Bedlam Theatre Staffing")

      client.account.sms.messages.create(
	:from => ChaosRails::Application.config.twilio_phone_number,
	:to => @user.phone_number,
	:body => "Hey! You're staffing #{job.name} at #{job.staffing.show_title}!"
	)
    end
  end
end
