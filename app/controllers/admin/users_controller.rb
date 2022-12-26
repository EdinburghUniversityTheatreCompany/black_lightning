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

  # BOOTSTRAP NICETOHAVE: Authentication....
  def autocomplete_list
    response.headers.delete('Content-Length')
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Content-Type'] = 'application/json'

    # Use the base_index_ransack_query to easily support ransacking the users.
    @users = base_index_ransack_query

    @users = @users.with_role(:member) if params[:all_users].nil?

    @users = @users.select(['id', :first_name, :last_name]).reorder(:first_name, :last_name)
    
    self.response_body = @users.map { |user| { id: user.id, text: user.name_or_default }}.to_json

    # Stop here. The old method is below.
    return
    # BOOTSTRAP NICETOHAVE: Figure out a way to use the below method, but while also retaining ordering since find_each ignores the order.

    # This... erm... thing... builds the response up one
    # user at a time, which saves loading the whole lot into
    # memory in one go. Unfortunately, it does mean doing some
    # of the JSON myself. Sorry.
    self.response_body = Enumerator.new do |output|
      output << '['

      first = true
      @users.find_each do |u|
        if first
          first = false
        else
          output << ','
        end

        output << "{\"id\":\"#{u.id}\",\"text\":\"#{u.name_or_default}\"}"
      end

      output << ']'
    end
  end

  private

  def permitted_params
    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    return [:email, :password, :password_confirmation, :remember_me, :first_name, :last_name, 
            :phone_number, :card_number, :public_profile, :bio, :avatar, :username, role_ids: []]
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
