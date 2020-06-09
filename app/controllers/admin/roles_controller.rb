class Admin::RolesController < AdminController
  load_and_authorize_resource

  def index
    @title = 'Roles'
  end

  def show
    @title = @role.name

    @q = @role.users.ransack(params[:q])

    @users = @q.result
               .accessible_by(current_ability)

    # Using a token is not the nicest way of handling it, but it works.
    @token = MembershipActivationToken.new
  end

  def new
    # The title is set by the view.
  end

  def create
    respond_to do |format|
      if @role.save
        format.html { redirect_to [:admin, @role], notice: 'Role was successfully created.' }
        format.json { render json: [:admin, @role], status: :created, location: @role }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @role.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
    # The title is set by the view.
  end

  def update
    respond_to do |format|
      if @role.update(role_params)
        format.html { redirect_to admin_role_url(@role), notice: 'Role was successfully updated.' }
        format.json { render json: [:admin, @role], status: :updated, location: @role }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @role.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    helpers.destroy_with_flash_message(@role)

    respond_to do |format|
      format.html { redirect_to admin_roles_path }
      format.json { format.json { head :no_content } }
    end
  end

  private

  def role_params
    params.require(:role).permit(:name)
  end
end
