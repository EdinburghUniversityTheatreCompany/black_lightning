class StaffingMailer < ActionMailer::Base
  default from: "webserver@bedlamtheatre.co.uk"

  def staffing_reminder(staffing)
    @staffing = staffing

    if @staffing.reminder_job.attempts > 0 then
      # Prevent the job from running more than once to prevent us spewing text messages
      # if there is an error.
      raise @staffing.reminder_job.last_error
    end

    # set up a client to talk to the Twilio REST API
    client = ::Twilio::REST::Client.new ChaosRails::Application.config.twilio_account_sid, ChaosRails::Application.config.twilio_auth_token

    errors = []

    staffing.staffing_jobs.each do |job|
      #Keep going to other users if sending to one fails for some reason.
      begin
        @user = job.user
        mail(:to => @user.email, :subject => "Bedlam Theatre Staffing")

        if @user.phone_number && (not @user.phone_number.blank?) then
          client.account.sms.messages.create(
            :from => ChaosRails::Application.config.twilio_phone_number,
            :to => @user.phone_number,
            :body => "Hey! You're staffing #{job.name} at #{job.staffing.show_title}!"
          )
        end
      rescue => e
        errors << e
      end
    end

    if errors then
      #Raise the errors now for the logs.
      errors.each do |e|
        raise e
      end
    end
  end
end
