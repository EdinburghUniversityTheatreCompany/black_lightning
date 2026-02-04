class UsersMailer < ApplicationMailer
  # Used for render_markdown and render_plain in the views
  helper :md

  def welcome_email(user)
    @user = user
    @subject = "Welcome to Bedlam Theatre"

    # Generate profile completion URL for incomplete profiles
    @profile_completion_url = if @user.profile_incomplete?
      profile_completion_url(token: @user.profile_completion_token, protocol: "https")
    else
      new_user_session_url(protocol: "https")
    end

    # Select editable block based on membership status
    block_name = @user.has_role?(:member) ? "Email - Welcome Email (Member)" : "Email - Welcome Email (Non-Member)"
    @editable_block = Admin::EditableBlock.find_by_name!(block_name)

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
