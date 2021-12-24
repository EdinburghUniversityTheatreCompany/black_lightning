class MembershipActivationTokensController < ApplicationController
  # Authorization on the account creation page would be a bit weird, eh?
  skip_authorization_check
  load_resource find_by: :token

  def activate
    @title = 'Activate Membership'
    @user = get_user

    if current_user&.has_role? :member
      flash[:error] = 'You have already activated your account.'
      raise(CanCan::AccessDenied, flash[:error])
    end
  end

  def submit
    @user = get_user

    @user.assign_attributes(user_params)

    if params[:consent]
      unless @user.save
        respond_to do |format|
          format.html { render 'activate', status: :unprocessable_entity }
          format.json { render json: user.errors, status: :unprocessable_entity }
        end
        return
      end

      @user.activate
      @user.touch(:consented)

      sign_out

      @membership_activation_token.destroy

      helpers.append_to_flash(:success, 'You have successfully (re)-activated your account! Please log in to continue.')

      redirect_to admin_url
    else
      helpers.append_to_flash(:error, 'You need to give consent before you can create an account.')

      render 'activate', status: :unprocessable_entity
    end
  end

  private

  def get_user
    return @membership_activation_token.user || User.new if current_user == @membership_activation_token.user

    if @membership_activation_token.user.nil?
      flash[:error] = 'This token belongs to a new user, but you are already signed in.'
    elsif current_user.nil?
      flash[:error] = 'This token belongs to an existing user, but you are not signed in. Please sign in and try again.'
    else
      flash[:error] = 'This token belongs to a different user.'
    end

    raise(CanCan::AccessDenied, flash[:error])
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :phone_number, :password, :public_profile, :bio, :avatar)
  end
end
