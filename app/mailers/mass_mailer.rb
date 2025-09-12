class MassMailer < ApplicationMailer
  helper(MdHelper)

  # TODO: Enable unsubscribing from mass mails. However, this is currently unused, so not urgent.

  def send_mail(mass_mail, recipient)
    @body    = mass_mail.body
    @subject = mass_mail.subject

    mail(to: [ recipient.email ], subject: "Bedlam Theatre - #{@subject}")
  end
end
