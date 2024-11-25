##
# Admin controller for User management.
##
class Admin::UsersController < AdminController
  include GenericController

  load_and_authorize_resource except: [:autocomplete_list]
  skip_load_resource only: [:create]

  ##
  # Overrides load_index_resources
  ##

  ##
  # GET /admin/users/1
  ##
  def show
    @title = @user.name(current_user)

    @team_memberships = @user.team_memberships(false)
    @link_to_admin_events = true

    super
  end

  ##
  # POST /admin/users
  ##
  def create
    # The user model has a special 'new' method that auto-generates a password if left blank.
    @user = User.new_user(create_params)

    super
  end

  def reset_password
    @user.send_reset_password_instructions

    respond_to do |format|
      flash[:succes] = 'Password reset instructions sent.'
      format.html { redirect_back fallback_location: admin_user_url(@user) }
    end
  end

  def autocomplete_list
    authorize! :read, User

    page = [params[:page].to_i, 1].max # First page is always 1.

    per_page = 30 # Adjust the number of items per page as needed

    # Ransack query should take care of the filtering.
    @users = base_index_ransack_query

    @users = @users.with_role(:member) if params[:show_non_members] != '1'

    @users = @users.reorder(:first_name, :last_name).page(page).per(per_page)

    items = @users.select(['id', :first_name, :last_name]).map do |user|
      { id: user.id, text: user.name_or_default }
    end

    total_count = @users.total_count

    render json: { results: items, pagination: { total_count: total_count, more: total_count > per_page * page } }
  end

  private

  def permitted_params
    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    perm_params = %i[email password password_confirmation remember_me first_name last_name
                     phone_number card_number public_profile bio avatar username]

    perm_params.push(role_ids: []) if current_user.has_role?(:admin)

    return perm_params
  end

  # TEST
  def base_index_database_query
    return super.with_role(:member) if params[:show_non_members] != '1'

    return super
  end

  def on_create_success
    super

    @user.send_welcome_email
  end
end
