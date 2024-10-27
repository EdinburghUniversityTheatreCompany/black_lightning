class MembershipActivationTokensController < ApplicationController
  # Authorization on the account creation page would be a bit weird, eh?
  skip_authorization_check
  load_resource find_by: :token

  def activate
    @title = 'Activate Membership'
    @user = get_user

    return unless current_user&.has_role?('Member')

    raise(CanCan::AccessDenied, 'You have already activated your account.')
  end

  def submit
    @user = get_user

    @user.assign_attributes(user_params)

    if params[:consent]
      unless @user.save
        respond_to do |format|
          format.html { render 'activate', status: :unprocessable_entity }
          # format.json { render json: user.errors, status: :unprocessable_entity }
        end
        return
      end

      @user.activate
      @user.touch(:consented)

      @membership_activation_token.destroy

      helpers.append_to_flash(:success, 'You have successfully (re)-activated your account! Please log in to continue.')

      @user.send_welcome_email

      redirect_to home_url
    # If not consented.
    else
      helpers.append_to_flash(:error, 'You need to accept the Terms and Conditions before continuing.')

      render 'activate', status: :unprocessable_entity
    end
  end

  private

  def get_user
    # The current_user is trying to reactivate themselves. That's allowed!
    if current_user.present? && current_user == @membership_activation_token.user
      return current_user
    # The current_user is not signed in, and is trying to activate an account that has not consented.
    # This means the account has either never been activated, or has not signed in for the consent period
    # (currently a year). This means we just assume that it's fine since they have the token, and
    # we let them reactivate.
    elsif current_user.nil? && @membership_activation_token.user.present? && @membership_activation_token.user.consented.blank?
      return @membership_activation_token.user
    elsif current_user.present? && @membership_activation_token.user.nil?
      error_message =  'This token belongs to a new user, but you are already logged in. You are not allowed to activate this account.'
    # The user is signed in but the token is not for them. Show an error.
    elsif current_user.present? && @membership_activation_token.user.present? && current_user != @membership_activation_token.user
      error_message =  'This token belongs to a different user. You are not allowed to activate this account.'
    # If the user is not signed in, but the token has a user, and that user has consented, they have signed in
    # recently enough that they should know their password and be able to sign in, or at least request a reset.
    elsif current_user.nil? && @membership_activation_token.user.present? && @membership_activation_token.user.consented
      error_message =  'This token belongs to an existing user, but you are not logged in. Please log in and try again.'
    else
      error_message =  'An unknown error occurred. You are not allowed to activate this account.'
    end

    # If we have not returned yet, that means there was an error.
    raise(CanCan::AccessDenied, error_message)
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :phone_number, :password, :public_profile, :bio, :avatar)
  end
end
