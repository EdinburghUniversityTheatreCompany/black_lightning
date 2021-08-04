class MembershipActivationTokenMailer < ApplicationMailer
  def send_activation(email, token)
    @token = token
    @subject = 'Bedlam Membership Activation'

    mail(to: email, subject: @subject)
  end
end
