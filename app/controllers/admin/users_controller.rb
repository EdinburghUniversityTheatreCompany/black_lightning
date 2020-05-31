##
# Admin controller for User management.
##
class Admin::UsersController < AdminController
  load_and_authorize_resource except: [:autocomplete_list]
  skip_load_resource only: [:create]
  ##
  # GET /admin/users
  ##
  def index
    @title = 'Users'

    @q     = User.ransack(params[:q])
    @users = @q.result(distinct: true)

    if params[:show_non_members] != '1'
      @users = @users.with_role(:member)
    end

    @users = @users.paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html
      format.json { render json: @users }
    end
  end

  ##
  # GET /admin/users/1
  ##
  def show
    @title = @user.name(current_user)

    @team_memberships = @user.team_memberships(false)
    @link_to_admin_events = true

    respond_to do |format|
      format.html
      format.json { render json: @user }
    end
  end

  ##
  # GET /admin/users/new
  ##
  def new
    # Title is set by the view.
  end

  ##
  # POST /admin/users
  ##
  def create
    @user = User.new_user(user_params)

    respond_to do |format|
      if @user.save
        format.html { redirect_to admin_user_url(@user) }
        format.json { render json: @user }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # GET /admin/users/1/edit
  ##
  def edit
    # The title is set by the view
  end

  ##
  # PUT /admin/users/1
  ##
  def update
    respond_to do |format|
      if @user.update(user_params)
        format.html { redirect_to admin_user_url(@user), notice: 'User was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/users/1
  ##
  def destroy
    helpers.destroy_with_flash_message(@user)

    respond_to do |format|
      format.html { redirect_to admin_users_path }
      format.json { head :no_content }
    end
  end

  def reset_password
    @user.send_reset_password_instructions

    respond_to do |format|
      format.html { redirect_back fallback_location: admin_user_url(@user), notice: 'Password reset instructions sent.' }
    end
  end

  def autocomplete_list
    response.headers.delete('Content-Length')
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Content-Type'] = 'application/json'

    @users = User.all

    @users = @users.with_role(:member) if params[:all_users].nil?

    @users = @users.select(['id', :first_name, :last_name])

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

        output << u.to_json
      end

      output << ']'
    end
  end

  private

  def user_params
    params[:user]
    params[:user][:password]
    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    return params.require(:user).permit(:email, :password, :password_confirmation, :remember_me, :first_name, :last_name,
                                        :phone_number, :card_number, :public_profile, :bio, :avatar, :username, role_ids: [])
  end
end
