class MembershipActivationTokenMailer < ApplicationMailer
  default reply_to: "Secretary <secretary@bedlamtheatre.co.uk>"

  def send_activation(email, token)
    @token = token
    @subject = "Bedlam Membership Activation"

    mail(to: email, subject: @subject)
  end
end
