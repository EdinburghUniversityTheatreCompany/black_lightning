class MassMailerPreview < ActionMailer::Preview
  def send_mail
    mass_mail = MassMail.all.sample || FactoryBot.create(:draft_mass_mail)
    recipients = User.all.sample

    MassMailer.send_mail(mass_mail, recipients)
  end
end
