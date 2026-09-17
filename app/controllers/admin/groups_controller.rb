class Admin::GroupsController < AdminController
  include GenericController

  load_resource
  authorize_resource except: [ :add_user, :remove_user ]
  before_action :authorize_add_user, only: [ :add_user ]
  before_action :authorize_remove_user, only: [ :remove_user ]

  def show
    @q = @group.users.ransack(params[:q], auth_object: current_ability)

    @users = @q.result

    super
  end

  def add_user
    user_id = params[:add_user_details][:user_id]

    user = User.find_by(id: user_id)

    if user.present?
      if user.in_group? @group
        helpers.append_to_flash(:success, "#{user.name(current_user)} already has the group of #{@group.name}")
      else
        user.join_group @group

        helpers.append_to_flash(:success, "#{user.name(current_user)} has been added to the group of #{@group.name}")
      end
    else
      helpers.append_to_flash(:error, "This user does not exist.")
    end

    @q = @group.users.ransack(nil, auth_object: current_ability)
    @users = @q.result

    respond_to do |format|
      format.html { redirect_to admin_group_url(@group) }
      format.turbo_stream
    end
  end

  def remove_user
    user_id = params[:user_id]
    user = User.find_by(id: user_id)

    if user.present?
      if user.in_group? @group.name
        user.leave_group @group
        helpers.append_to_flash(:success, "#{user.name(current_user)} has been removed from the group of #{@group.name}")
      else
        helpers.append_to_flash(:warning, "#{user.name(current_user)} was not in the group of #{@group.name}")
      end
    else
      helpers.append_to_flash(:error, "This user does not exist.")
    end

    redirect_to admin_group_url(@group)
  end

  # Purge removes all users currently on the group from the group, while leaving the group and permissions intact.
  def purge
    if @group.purge
      helpers.append_to_flash(:success, "All users have been removed from the group '#{@group.name}'")
    else
      helpers.append_to_flash(:error, "Something went wrong removing all users from '#{@group.name}'")
    end

    redirect_to admin_group_url(@group)
  end

  # Archive moves all users currently on the group to a group labelled with the current academic year.
  # For example 'Members' -> 'Members 23/24'. The new group has no permissions, and the old group keeps all permissions.
  def archive
    if @group.archive(helpers.academic_year_shorthand)
      helpers.append_to_flash(:success, "Archived all users with the group '#{@group.name}'")
    else
      helpers.append_to_flash(:error, "Something went wrong archiving all users with the group '#{@group.name}'")
    end

    redirect_to admin_group_url(@group)
  end

  def destroy
    if @group.destroy
      helpers.append_to_flash(:success, "The group '#{@group.name}' was successfully deleted.")
      redirect_to admin_groups_path
    else
      helpers.append_to_flash(:error, @group.errors.full_messages.join(", "))
      redirect_to admin_group_path(@group)
    end
  end

  private

  def authorize_add_user
    # Load the group manually since load_resource might not work for custom actions
    @group ||= Group.find(params[:id])
    authorize! :add_user, @group
  end

  def authorize_remove_user
    # Load the group manually since load_resource might not work for custom actions
    @group ||= Group.find(params[:id])
    authorize! :remove_user, @group
  end

  def permitted_params
    [ :name, children_attributes: [ :id, :_destroy, :name ], parents_attributes: [ :id, :_destroy, :name ] ]
  end

  def order_args
    [ "name" ]
  end
end
