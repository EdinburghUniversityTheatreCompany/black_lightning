class UsersMailer < ApplicationMailer
  def welcome_email(user, reset_password)
    @user = user
    @reset_password = reset_password

    @subject = 'Welcome to Bedlam Theatre'

    mail(to: @user.email, subject: @subject)
  end
end
