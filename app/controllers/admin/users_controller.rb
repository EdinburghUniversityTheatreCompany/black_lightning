class Admin::UsersController < AdminController
  load_and_authorize_resource
  def index
    @title = "Users"
    @users = User.all
  end

  def show
    @user = User.find(params[:id])
    @title = @user.name
  end

  def new
    @user = User.new
    @title = "New User"
  end

  def create
    params[:user].delete(:password) if params[:user][:password].blank?
    params[:user].delete(:password_confirmation) if params[:user][:password_confirmation].blank?

    respond_to do |format|
      if @user = User.create_user(params[:user])
        format.html {redirect_to admin_user_url(@user)}
      else
        format.html {render "new"}
      end
    end
  end

  def edit
    @user = User.find(params[:id])
    @title = "Editing #{@user.name}"
  end

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

  def destroy
    @user = User.find(params[:id])
    @user.destroy

    respond_to do |format|
      format.html {redirect_to admin_users_path}
    end
  end
end
