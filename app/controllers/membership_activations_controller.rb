class MembershipActivationsController < ApplicationController

  def new
    authorize! :create, MembershipActivationToken
    @user = User.new
  end

  def create
    authorize! :create, MembershipActivationToken
    @user = User.find_by(email: params[:user][:email])

    if @user.present?
      token = MembershipActivationToken.create!(user: @user)
    else
      token = MembershipActivationToken.create!
    end
    MembershipActivationMailer.send_activation(params[:user][:email], token).deliver_now

    redirect_to new_membership_activation_path, notice: 'Mail sent to member'
  end

  def edit
    @token = MembershipActivationToken.find_by!(token: params[:id])
    @user = User.new
  end

  def update
    if params[:consent]
      @token = MembershipActivationToken.find_by!(token: params[:id])
      if @token.user
        user = @token.user
      else
        user = User.create!(user_params)
      end

      user.add_role :member
      user.touch(:consented)
      sign_out

      @token.destroy
      redirect_to admin_url
    else
      redirect_to edit_membership_activation_path(params[:id]), notice: "Consent is required to register on this website"
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name)
  end
end