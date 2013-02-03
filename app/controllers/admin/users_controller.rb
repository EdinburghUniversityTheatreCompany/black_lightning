##
# Admin controller for User management.
##
class Admin::UsersController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/users
  ##
  def index
    @title = "Users"

    if params[:show_non_members] == "true"
      @users = User
    else
      @users = User.with_role(:member)
    end

    if params[:search]
      q = "%#{params[:search]}%"
      @users = @users.where("first_name like ? or last_name like ?", q, q)
    end

    @users = @users.paginate(:page => params[:page], :per_page => 15)

    @users = @users.all
  end

  ##
  # GET /admin/users/1
  ##
  def show
    @user = User.find(params[:id])
    @title = @user.name
  end

  ##
  # GET /admin/users/new
  ##
  def new
    @user = User.new
    @title = "New User"
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
        format.html {redirect_to admin_user_url(@user)}
      else
        format.html {render "new"}
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
        if can? :read, User then
          format.html { redirect_to admin_user_url(@user), notice: 'User was successfully updated.' }
        else
          format.html { redirect_to admin_url, notice: 'User was successfully updated.' }
        end
      else
        format.html { render "edit" }
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
      format.html {redirect_to admin_users_path}
    end
  end

  def reset_password
    @user = User.find(params[:id])
    @user.send_reset_password_instructions

    respond_to do |format|
      format.html { redirect_to admin_user_url(@user), notice: 'Password reset instructions sent.' }
    end
  end
end
