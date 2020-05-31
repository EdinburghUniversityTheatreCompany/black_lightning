class MassMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'
  add_template_helper(MdHelper)

  def send_mail(mass_mail, recipient)
    @body    = mass_mail.body
    @subject = mass_mail.subject

    mail(to: [recipient.email], subject: "Bedlam Theatre - #{@subject}")
  end
end
