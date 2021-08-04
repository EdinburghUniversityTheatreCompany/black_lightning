class UsersMailerPreview < ActionMailer::Preview
  def welcome_email
    user = User.all.sample
    reset_password = [true, false].sample

    UsersMailer.welcome_email(user, reset_password)
  end
end
