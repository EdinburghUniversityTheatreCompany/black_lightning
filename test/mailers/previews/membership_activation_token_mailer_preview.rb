class MembershipActivationTokenMailerPreview < ActionMailer::Preview
  def send_activation
    email = 'finbar@viking.arr'
    token = MembershipActivationToken.create

    MembershipActivationTokenMailer.send_activation(email, token)
  end
end
