class Admin::RolesController < AdminController
  include GenericController

  load_and_authorize_resource

  def show
    # Using a token is not the nicest way of handling the adding, but it works.
    # It's a bit annoying because /shared/form/user_field needs a model to work.
    @token = MembershipActivationToken.new

    super
  end

  def add_user
    user_id = params[:membership_activation_token][:user_id]

    user = User.find_by(id: user_id)

    if user.present?
      if user.has_role? @role.name
        helpers.append_to_flash(:success, "#{user.name(current_user)} already has the role of #{@role.name}")
      else
        user.add_role @role.name

        helpers.append_to_flash(:success, "#{user.name(current_user)} has been added to the role of #{@role.name}")
      end
    else
      helpers.append_to_flash(:error, 'This user does not exist.')
    end

    redirect_to admin_role_url(@role)
  end

  def purge
    @role.purge

    helpers.append_to_flash(:success, "All users have been removed from the Role '#{@role.name}'")

    redirect_to admin_role_url(@role)
  end

  private

  def permitted_params
    [:name]
  end

  def order_args
    :name
  end
end
