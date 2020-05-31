class Admin::MembershipActivationTokensController < AdminController
  authorize_resource

  def new
    @user = User.new
    @token = MembershipActivationToken.new
    # Title is set by the view.
  end

  def create_activation
    @token = MembershipActivationToken.new

    email = params[:user][:email]

    @user = User.find_by(email: email)

    if @user.present?
      base_message = "The email #{email} is already in use by #{@user.name(current_user)}"

      if @user.has_role? :member
        flash[:error] = "#{base_message} and they already are a member. They will not be send an activation mail."

        return render_on_fail
      end

      flash[:success] = "#{base_message}. They will be send a reactivation mail."

      return unless add_user_to_token
    end

    @token.save
    MembershipActivationTokenMailer.send_activation(email, @token).deliver_later

    flash[:success] ||= "Activation Mail send to #{email}"
    redirect_to new_admin_membership_activation_token_path
  end

  def create_reactivation
    @token = MembershipActivationToken.new

    user_id = params[:membership_activation_token][:user_id]

    begin
      @user = User.find(user_id)
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "There is no user with the specified ID. Are you sure the name '#{params[:membership_activation_token][:user_name_field]}' is correct?"

      return render_on_fail
    end

    if @user.has_role? :member
      flash[:error] = "#{@user.name(current_user)} already is a member and will not be send a reactivation mail."

      return render_on_fail
    end

    email = @user.email

    if email.downcase.include?('bedlamtheatre.co.uk') && email.downcase.include?('unknown')
      flash[:error] = 'This user had their email removed or was exported from the old website. Please ask them for their email, update their user record with the email they give you, and try again. Do not create a new account for them, but reactivate their old one instead.'

      return render_on_fail
    end

    @token.user = @user
    @token.save
    MembershipActivationTokenMailer.send_activation(@user.email, @token).deliver_later

    flash[:success] = "Reactivation Mail send to #{@user.name(current_user)} at #{@user.email}"
    redirect_to new_admin_membership_activation_token_path
  end

  private

  def add_user_to_token
    unless @token.update_attribute(:user, @user)
      # This will probably not happen, but here is a nice error just in case.
      # :nocov:
      flash[:error] = 'There was an error assigning the user to the token'

      render_on_fail

      return false
      # :nocov:
    end

    return true
  end

  def render_on_fail
    @user = User.new if @user.nil?

    respond_to do |format|
      format.html { render 'new', status: :unprocessable_entity }
      format.json { render json: flash[:error], status: :unprocessable_entity }
    end
  end
end
