class MembershipActivationMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def send_activation(email, token)
    @token = token

    mail(to: email, subject: 'Bedlam Membership Activation')
  end
end
