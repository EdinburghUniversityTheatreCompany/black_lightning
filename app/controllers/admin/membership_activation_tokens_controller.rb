class Admin::MembershipActivationTokensController < AdminController
  # Be careful that authorization happens correctly / is executed on the model when adding more actions.
  authorize_resource

  def new
    @user = User.new
    @token = MembershipActivationToken.new
    @title = 'Membership Activation'
  end

  # TODO: This should be abstracted into a model so this can also be called from other logic things in case of a mass reactivation.
  def create_activation
    # Has to be created early in case it is needed in render_on_fail
    @token = MembershipActivationToken.new
    
    email = params[:user][:email]
    first_name = params[:user][:first_name]
    last_name = params[:user][:last_name]

    unless email.present? && first_name.present? && last_name.present?
      helpers.append_to_flash(:error, 'Please fill in all fields.')

      return render_on_fail
    end

    # Try to find the user by their email.
    @user = User.find_by(email: email)

    # If the user exists, check if they are already a member.
    if @user.present?
      base_message = "The email #{email} is already in use by #{@user.name(current_user)}"

      if @user.has_role?('Member')
        helpers.append_to_flash(:error, "#{base_message} and they already are a member. They will not be send an activation mail.")

        return render_on_fail
      end

      base_message = "#{base_message}. They will be send a reactivation mail."
    # If we cannot find a user by their email, try to find them by their name.
    else
      @user = User.find_by(first_name: first_name, last_name: last_name)
    
      # If a user with this name exists, do not proceed, but warn.
      if @user.present?
        helpers.append_to_flash(:error, "Found a user with the name '#{first_name} #{last_name}\' but with the email '#{@user.email}'. If this is the user you are trying to activate, please enter this email instead. If this is not the same user, please enter their name again and 'AGAIN' to the end of the last name.")

        return render_on_fail
      # If no user with this email or name exists, create a user with the basic information specified by the secretary so they can be tracked.
      else
        @user = User.new_user(email: email, first_name: first_name, last_name: last_name.delete_suffix('AGAIN'))
        @user.save

        base_message = "Activation Mail sent to #{email}"
      end
    end

    @token.user = @user

    # If this fails, we might have created a user above, but this user will be found if the
    # form is resubmitted, so this is okay.
    if @token.save
      MembershipActivationTokenMailer.send_activation(email, @token).deliver_later

      helpers.append_to_flash(:success, base_message)

      redirect_to new_admin_membership_activation_token_path
    else
      render_on_fail
    end
  end

  def create_reactivation
    @token = MembershipActivationToken.new

    user_id = params[:membership_activation_token][:user_id]

    begin
      @user = User.find(user_id)
    rescue ActiveRecord::RecordNotFound
      helpers.append_to_flash(:error, "There is no user with the specified ID. Are you sure the name '#{params[:membership_activation_token][:user_name_field]}' is correct?")

      return render_on_fail
    end

    if @user.has_role?('Member')
      helpers.append_to_flash(:error, "#{@user.name(current_user)} already is a member and will not be send a reactivation mail.")

      return render_on_fail
    end

    email = @user.email

    if email.downcase.include?('bedlamtheatre.co.uk') && email.downcase.include?('unknown')
      helpers.append_to_flash(:error, 'This user had their email removed or was exported from the old website. Please ask them for their email, update their user record with the email they give you, and try again. Do not create a new account for them, but reactivate their old one instead.')

      return render_on_fail
    end

    @token.user = @user
    @token.save
    MembershipActivationTokenMailer.send_activation(@user.email, @token).deliver_later

    helpers.append_to_flash(:success, "Reactivation Mail sent to #{@user.name(current_user)} at #{@user.email}")

    redirect_to new_admin_membership_activation_token_path
  end

  private

  def render_on_fail
    @user = User.new if @user.nil?

    respond_to do |format|
      format.html { render 'new', status: :unprocessable_entity }
      # format.json { render json: flash[:error], status: :unprocessable_entity }
    end
  end
end
