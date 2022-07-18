class UsersMailer < ApplicationMailer
  # EMAIL: This is currently never sent. Sent it once a User is created, whether this is after activation or not.
  def welcome_email(user, reset_password)
    @user = user
    @reset_password = reset_password

    @subject = 'Welcome to Bedlam Theatre'

    mail(to: @user.email, subject: @subject)
  end
end
