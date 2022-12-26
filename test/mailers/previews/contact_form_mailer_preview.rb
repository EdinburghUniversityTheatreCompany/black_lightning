class ContactFormMailerPreview < ActionMailer::Preview
  def contact_form_send
    sender_email = 'sender@bedlamtheatre.co.uk'
    name = 'Finbar the Viking'
    recipient_email = 'recipient@bedlamtheatre.co.uk'
    subject = 'To Preview or not to Preview'
    message = 'Is what Shakespeare would have said had he gone to Fringe'

    ContactFormMailer.contact_form_mail(sender_email, recipient_email, name, subject, message).deliver_now
  end
end
