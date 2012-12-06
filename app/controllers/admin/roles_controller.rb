class Admin::RolesController < AdminController

  load_and_authorize_resource

  def index
    @title = "Roles"
    @roles = Role.all
  end

  def show
    @role = Role.find(params[:id])
  end

  def new
    @role = Role.new
  end

  def create
    @role = Role.new(params[:role])

    respond_to do |format|
      if @role.save
        format.html { redirect_to [:admin, @role], notice: 'Role was successfully created.' }
        format.json { render json: [:admin, @role], status: :created, location: @role }
      else
        format.html { render "new" }
        format.json { render json: @role.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @role = Role.find(params[:id])
  end

  def update
    @role = Role.find(params[:id])

    respond_to do |format|
      if @role.update_attributes(params[:role])
        format.html { redirect_to admin_role_url(@role), notice: 'Role was successfully updated.' }
      else
        format.html { render "edit" }
      end
    end
  end

  def destroy
    @role = Role.find(params[:id])
    @role.destroy

    respond_to do |format|
      format.html {redirect_to admin_roles_path}
    end
  end
end
