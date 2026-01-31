class UsersMailer < ApplicationMailer
  # Used for render_markdown and render_plain in the views
  helper :md

  def welcome_email(user)
    @user = user
    @subject = "Welcome to Bedlam Theatre"

    # Select editable block based on membership status
    block_name = @user.has_role?(:member) ? "Email - Welcome Email (Member)" : "Email - Welcome Email (Non-Member)"
    @editable_block = Admin::EditableBlock.find_by_name!(block_name)

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
