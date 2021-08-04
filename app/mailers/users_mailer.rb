class UsersMailer < ApplicationMailer
  def welcome_email(user, reset_password)
    @user = user
    @reset_password = reset_password

    mail(to: @user.email, subject: 'Welcome to Bedlam Theatre')
  end
end
