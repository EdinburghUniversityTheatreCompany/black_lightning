class Admin::StaffingsController < AdminController
  
  load_and_authorize_resource :class => Admin::Staffing
  
  # GET /admin/staffings
  # GET /admin/staffings.json
  def index
    @admin_staffings = Admin::Staffing.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_staffings }
    end
  end

  # GET /admin/staffings/1
  # GET /admin/staffings/1.json
  def show
    @admin_staffing = Admin::Staffing.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_staffing }
    end
  end

  # GET /admin/staffings/new
  # GET /admin/staffings/new.json
  def new
    @users = User.accessible_by(current_ability, :manage) 
    @admin_staffing = Admin::Staffing.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @admin_staffing }
    end
  end

  # GET /admin/staffings/1/edit
  def edit
    @users = User.accessible_by(current_ability, :manage) 
    @admin_staffing = Admin::Staffing.find(params[:id])
  end

  # POST /admin/staffings
  # POST /admin/staffings.json
  def create
    @admin_staffing = Admin::Staffing.new(params[:admin_staffing])

    respond_to do |format|
      if @admin_staffing.save
        format.html { redirect_to edit_admin_staffing_path(@admin_staffing), notice: 'Staffing was successfully created.' }
        format.json { render json: @admin_staffing, status: :created, location: @admin_staffing }
      else
        format.html { render action: "new" }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/staffings/1
  # PUT /admin/staffings/1.json
  def update
    @admin_staffing = Admin::Staffing.find(params[:id])

    respond_to do |format|
      if @admin_staffing.update_attributes(params[:admin_staffing])
        format.html { redirect_to edit_admin_staffing_path(@admin_staffing), notice: 'Staffing was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/staffings/1
  # DELETE /admin/staffings/1.json
  def destroy
    @admin_staffing = Admin::Staffing.find(params[:id])
    @admin_staffing.destroy

    respond_to do |format|
      format.html { redirect_to admin_staffings_url }
      format.json { head :no_content }
    end
  end
end
