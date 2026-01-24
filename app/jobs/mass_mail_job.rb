class MassMailJob < ApplicationJob
  queue_as :mailers

  def perform(mass_mail_id)
    mass_mail = MassMail.find(mass_mail_id)

    # Each email is enqueued as a separate job so it can be retried independently
    # if rate limited. ApplicationJob handles retry with exponential backoff.
    mass_mail.recipients.each do |recipient|
      MassMailer.send_mail(mass_mail, recipient).deliver_later
    end
  end
end
