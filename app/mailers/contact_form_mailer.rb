class ContactFormMailer < ApplicationMailer
  def contact_form_mail(sender_email, recipient_email, name, subject, message)
    @message = message
    @name = name
    @recipient_email = recipient_email
  
    mail(to: [sender_email, recipient_email], subject: subject, reply_to: sender_email)
  end
end
