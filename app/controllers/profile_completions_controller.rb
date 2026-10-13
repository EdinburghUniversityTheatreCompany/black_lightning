class ProfileCompletionsController < ApplicationController
  # Authorization would be problematic here since the whole point is to complete a profile
  skip_authorization_check

  def show
    @user = find_user_for_profile_completion
    @title = "Complete Your Profile"
  end

  def update
    @user = find_user_for_profile_completion

    unless params[:consent]
      helpers.append_to_flash(:error, "You need to accept the Terms and Conditions before continuing.")
      render :show, status: :unprocessable_entity
      return
    end

    @user.assign_attributes(user_params)

    unless @user.save
      render :show, status: :unprocessable_entity
      return
    end

    @user.complete_profile!
    @user.send_welcome_email

    sign_in(@user) unless user_signed_in?

    helpers.append_to_flash(:success, "Your profile has been completed successfully!")
    redirect_to admin_path
  end

  private

  def find_user_for_profile_completion
    # From the emailed link.
    if params[:token].present?
      user = User.find_by_profile_completion_token(params[:token])
      raise ActiveRecord::RecordNotFound, "Invalid or expired profile completion token" unless user

      if current_user.present? && current_user != user
        raise CanCan::AccessDenied, "This profile completion link belongs to a different user."
      end

      return user
    end

    if current_user.present?
      if current_user.profile_complete?
        raise CanCan::AccessDenied, "You have already completed your profile."
      end

      return current_user
    end

    raise CanCan::AccessDenied, "You need to be logged in or have a valid profile completion link to access this page."
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name, :phone_number, :bio, :avatar, :public_profile)
  end
end
