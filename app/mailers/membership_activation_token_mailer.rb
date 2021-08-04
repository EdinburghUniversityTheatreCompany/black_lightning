class MembershipActivationTokenMailer < ApplicationMailer
  def send_activation(email, token)
    @token = token

    mail(to: email, subject: 'Bedlam Membership Activation')
  end
end
