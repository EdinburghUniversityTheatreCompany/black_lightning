##
# Admin controller for User management.
##
class Admin::UsersController < AdminController
  include GenericController

  load_and_authorize_resource except: [ :autocomplete_list ]
  skip_load_resource only: [ :create ]

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
      flash[:succes] = "Password reset instructions sent."
      format.html { redirect_back fallback_location: admin_user_url(@user) }
    end
  end

  def merge
    @title = "Merge User Into #{@user.name_or_email}"

    # If source_user_id is provided (e.g., from duplicates view), pre-load for preview
    if params[:source_user_id].present?
      @source_user = User.find_by(id: params[:source_user_id])
    end
  end

  def merge_preview
    # Redirect to merge with source_user_id in URL so URL reflects state
    redirect_to merge_admin_user_path(@user, source_user_id: params[:source_user_id])
  end

  def absorb
    source_user = User.find(params[:source_user_id])
    keep_from_source = params[:keep_from_source] || []
    result = @user.absorb(source_user, keep_from_source: keep_from_source)

    respond_to do |format|
      if result[:success]
        flash[:success] = "Successfully merged #{source_user.name_or_email} into #{@user.name_or_email}"
        format.html { redirect_to admin_user_url(@user) }
      else
        flash[:error] = result[:errors].join(", ")
        format.html { redirect_back fallback_location: admin_user_url(@user) }
      end
    end
  end

  def autocomplete_list
    authorize! :autocomplete, User

    page = [ params[:page].to_i, 1 ].max # First page is always 1.

    per_page = 30 # Adjust the number of items per page as needed

    # Ransack query should take care of the filtering.
    @users = base_index_ransack_query

    @users = @users.with_role(:member) if params[:show_non_members] != "1"

    # Exclude specific user (e.g., when selecting merge source, exclude target)
    @users = @users.where.not(id: params[:exclude_id]) if params[:exclude_id].present?

    @users = @users.reorder(:first_name, :last_name).page(page).per(per_page)

    items = @users.select([ "id", :first_name, :last_name ]).map do |user|
      { id: user.id, text: user.name_or_default }
    end

    total_count = @users.total_count

    render json: { results: items, pagination: { total_count: total_count, more: total_count > per_page * page } }
  end

  ##
  # GET /admin/users/activate
  ##
  def activate
    authorize! :create, User

    @user = User.new
    @title = "Activate Members"
  end

  ##
  # POST /admin/users/activate
  ##
  def create_activation
    authorize! :create, User

    # Handle both new user creation and resend
    if params[:user_id].present?
      # Resend to existing user
      user = User.find(params[:user_id])
      user.send_welcome_email

      helpers.append_to_flash(:success, "Profile completion email resent to #{user.email}")
      redirect_to activate_admin_users_path
    else
      # Create new user
      @user = User.new_user(activation_user_params)
      @user.add_role(:member) if params[:user][:is_member] == "1"

      if @user.save
        @user.send_welcome_email
        helpers.append_to_flash(:success, "User created and profile completion email sent to #{@user.email}")
        redirect_to activate_admin_users_path
      else
        @title = "Activate Members"
        render :activate, status: :unprocessable_entity
      end
    end
  end

  ##
  # POST /admin/users/resend_activation
  ##
  def resend_activation
    authorize! :create, User

    user = User.find(params[:user_id])
    user.send_welcome_email

    helpers.append_to_flash(:success, "Profile completion email resent to #{user.email}")
    redirect_to activate_admin_users_path
  end

  private

  def permitted_params
    if params[:user][:password].blank?
      params[:user].delete(:password)
    elsif @user&.persisted? && @user.valid_password?(params[:user][:password])
      # If password is the same as current, treat as if blank (only for existing users)
      params[:user].delete(:password)
    end

    if params[:user][:password_confirmation].blank?
      params[:user].delete(:password_confirmation)
    elsif params[:user][:password].blank? && params[:user][:password_confirmation].present?
      # If password was removed but confirmation wasn't, remove confirmation too
      params[:user].delete(:password_confirmation)
    end

    perm_params = %i[email password password_confirmation remember_me first_name last_name
                     phone_number card_number public_profile bio avatar username student_id associate_id]

    perm_params.push(role_ids: []) if current_user.has_role?(:admin)

    perm_params
  end

  # TEST
  def base_index_database_query
    return super.with_role(:member) if params[:show_non_members] != "1"

    super
  end

  def on_create_success
    super

    @user.send_welcome_email
  end

  def activation_user_params
    params.require(:user).permit(:email, :first_name, :last_name, :student_id, :associate_id)
  end
end
