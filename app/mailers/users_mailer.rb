class UsersMailer < ActionMailer::Base
  default from: "Bedlam Theatre <no-reply@bedlamtheatre.co.uk>"

  def welcome_email(user, reset_password)
    @user = user
    @reset_password = reset_password

    mail(:to => @user.email, :subject => "Welcome to Bedlam Theatre",
        :reply_to => "IT Systems Manager <it@bedlamtheatre.co.uk>")
  end
end
