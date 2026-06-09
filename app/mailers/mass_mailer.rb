class MassMailer < ApplicationMailer
  helper(MdHelper)

  # TODO: Enable unsubscribing from mass mails. However, this is currently unused, so not urgent.

  def send_mail(mass_mail, recipient_email)
    @body    = mass_mail.body
    @subject = mass_mail.subject

    mail(to: [ recipient_email ], subject: "Bedlam Theatre - #{@subject}")
  end
end
