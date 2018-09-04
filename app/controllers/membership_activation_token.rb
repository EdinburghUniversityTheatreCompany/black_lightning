class MembershipActivationController < ApplicationController
  def create
    authorize! :create, MembershipActivationToken
    @user = User.find(email: params[:email])

    if @user.present?
      MembershipActivationToken.create!(user: @user)
    end
    MembershipActivationMailer.reset_mail(params[:email], @user).deliver_now

    redirect_to new_password_reset_path, notice: 'Please check your email' # TODO set a new path for this
  end

  def edit
    @token = MembershipActivationToken.find_by!(token: params[:id])
  end

  def update
    @token = MembershipActivationToken.find_by!(token: params[:id])
    if @token.user?
      user = @token.user
    else
      #TODO read in parameters and create user
    end

    user.add_role :member

    redirect_to admin_path
  end

  private

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name)
  end
end