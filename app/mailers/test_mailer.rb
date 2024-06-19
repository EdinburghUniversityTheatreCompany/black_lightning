class TestMailer < ApplicationMailer
  default reply_to: 'IT <it@bedlamtheatre.co.uk>'

  def test_email(email_address)
    return mail(to: email_address, subject: 'Check In', content_type: "text/plain")
  end
end
