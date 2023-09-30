class Admin::RolesController < AdminController
  include GenericController

  load_and_authorize_resource

  def show
    @q = @role.users.ransack(params[:q], auth_object: current_ability)

    @users = @q.result
               .accessible_by(current_ability)

    super
  end

  def add_user
    user_id = params[:add_user_details][:user_id]

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
    ['name']
  end
end
