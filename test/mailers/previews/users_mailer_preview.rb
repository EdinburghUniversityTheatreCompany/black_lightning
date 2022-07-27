class UsersMailerPreview < ActionMailer::Preview
  def welcome_email
    user = User.all.sample

    UsersMailer.welcome_email(user)
  end
end
