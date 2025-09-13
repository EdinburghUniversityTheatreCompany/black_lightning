class MassMailJob < ApplicationJob
  queue_as :mailers

  def perform(mass_mail_id)
    mass_mail = MassMail.find(mass_mail_id)

    mass_mail.recipients.each do |recipient|
      begin
        MassMailer.send_mail(mass_mail, recipient).deliver_now
      rescue => e
        Rails.logger.fatal e.message
        # Continue sending to other recipients even if one fails
      end
    end
  end
end
