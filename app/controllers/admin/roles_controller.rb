class Admin::RolesController < AdminController
  include GenericController

  load_and_authorize_resource

  def show
    @q = @role.users.ransack(params[:q], auth_object: current_ability)

    @users = @q.result

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
      helpers.append_to_flash(:error, "This user does not exist.")
    end

    redirect_to admin_role_url(@role)
  end

  def remove_user
    user_id = params[:user_id]
    user = User.find_by(id: user_id)

    if user.present?
      if user.has_role? @role.name
        @role.remove_user(user)
        helpers.append_to_flash(:success, "#{user.name(current_user)} has been removed from the role of #{@role.name}")
      else
        helpers.append_to_flash(:warning, "#{user.name(current_user)} was not in the role of #{@role.name}")
      end
    else
      helpers.append_to_flash(:error, "This user does not exist.")
    end

    redirect_to admin_role_url(@role)
  end

  # Purge removes all users currently on the role from the role, while leaving the role and permissions intact.
  def purge
    if @role.purge
      helpers.append_to_flash(:success, "All users have been removed from the Role '#{@role.name}'")
    else
      helpers.append_to_flash(:error, "Something went wrong removing all users from '#{@role.name}'")
    end

    redirect_to admin_role_url(@role)
  end

  # Archive moves all users currently on the role to a role labelled with the current academic year.
  # For example 'Members' -> 'Members 23/24'. The new role has no permissions, and the old role keeps all permissions.
  def archive
    if @role.archive(helpers.academic_year_shorthand)
      helpers.append_to_flash(:success, "Archived all users with the Role '#{@role.name}'")
    else
      helpers.append_to_flash(:error, "Something went wrong archiving all users with the Role '#{@role.name}'")
    end

    redirect_to admin_role_url(@role)
  end

  private

  def permitted_params
    [ :name ]
  end

  def order_args
    [ "name" ]
  end
end
