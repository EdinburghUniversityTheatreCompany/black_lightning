##
# Admin controller for User management.
##
class Admin::UsersController < AdminController
  load_and_authorize_resource except: [:autocomplete_list]

  ##
  # GET /admin/users
  ##
  def index
    @title = 'Users'

    @q     = User.unscoped.search(params[:q])
    @users = @q.result(distinct: true)

    if params[:show_non_members] != '1'
      @users = @users.with_role(:member)
    end

    @users = @users.paginate(page: params[:page], per_page: 15)
    @users = @users.all

    respond_to do |format|
      format.html
      format.json { render json: @users }
    end
  end

  ##
  # GET /admin/users/1
  ##
  def show
    @user = User.find(params[:id])
    @title = @user.name

    respond_to do |format|
      format.html
      format.json { render json: @user }
    end
  end

  ##
  # GET /admin/users/new
  ##
  def new
    @user = User.new
    @title = 'New User'
  end

  ##
  # POST /admin/users
  ##
  def create
    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    @user = User.create_user(params[:user])

    respond_to do |format|
      if @user.save
        format.html { redirect_to admin_user_url(@user) }
        format.json { render json: @user }
      else
        format.html { render 'new' }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # GET /admin/users/1/edit
  ##
  def edit
    @user = User.find(params[:id])
    @title = "Editing #{@user.name}"
  end

  ##
  # PUT /admin/users/1
  ##
  def update
    @user = User.find(params[:id])

    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    respond_to do |format|
      if @user.update_attributes(params[:user])
        if can? :read, User
          format.html { redirect_to admin_user_url(@user), notice: 'User was successfully updated.' }
        else
          format.html { redirect_to admin_url, notice: 'User was successfully updated.' }
        end
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/users/1
  ##
  def destroy
    @user = User.find(params[:id])
    @user.destroy

    respond_to do |format|
      format.html { redirect_to admin_users_path }
      format.json { head :no_content }
    end
  end

  def reset_password
    @user = User.find(params[:id])
    @user.send_reset_password_instructions

    respond_to do |format|
      format.html { redirect_to admin_user_url(@user), notice: 'Password reset instructions sent.' }
    end
  end

  def autocomplete_list
    response.headers.delete('Content-Length')
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Content-Type'] = 'application/json'

    @users = User.with_role(:member).select(['id', :first_name, :last_name])

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
end
