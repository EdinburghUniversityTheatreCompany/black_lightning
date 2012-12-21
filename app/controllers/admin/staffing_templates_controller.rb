##
# Controller for Admin::StaffingTemplate. More details can be found there.
##
class Admin::StaffingTemplatesController < AdminController

  load_and_authorize_resource :class => Admin::StaffingTemplate

  ##
  # GET /admin/staffing_templates
  #
  # GET /admin/staffing_templates.json
  ##
  def index
   @templates = Admin::StaffingTemplate.all
    @title = "Staffing Templates"
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json:@templates }
    end
  end

  ##
  # GET /admin/staffing_templates/1
  #
  # GET /admin/staffing_templates/1.json
  ##
  def show
   @template = Admin::StaffingTemplate.find(params[:id])
    @title = "Staffing Templates"
    respond_to do |format|
      format.html # show.html.erb
      format.json { render :json => @template.to_json(:include => { :staffing_jobs => {} }) }
    end
  end

  ##
  # GET /admin/staffing_templates/new
  #
  # GET /admin/staffing_templates/new.json
  ##
  def new
    @users = User.all
   @template = Admin::StaffingTemplate.new
    @title = "New Staffing Template"
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json:@template }
    end
  end

  ##
  # GET /admin/staffing_templates/1/edit
  ##
  def edit
    @template = Admin::StaffingTemplate.find(params[:id])
    @title = "Editing Staffing Template"
  end

  ##
  # POST /admin/staffing_templates
  #
  # POST /admin/staffing_templates.json
  ##
  def create
    @template = Admin::StaffingTemplate.new(params[:admin_staffing_template])

    respond_to do |format|
      if@template.save
        flash[:success] = 'Staffing template was successfully created.'
        format.html { redirect_to admin_staffing_template_path(@template) }
        format.json { render json:@template, status: :created, location: @template }
      else
        format.html { render "new" }
        format.json { render json:@template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/staffing_templates/1
  #
  # PUT /admin/staffing_templates/1.json
  ##
  def update
   @template = Admin::StaffingTemplate.find(params[:id])

    respond_to do |format|
      if@template.update_attributes(params[:admin_staffing_template])
        flash[:success] = 'Staffing template was successfully updated.'
        format.html { redirect_to admin_staffing_template_path(@template) }
        format.json { head :no_content }
      else
        format.html { render "edit" }
        format.json { render json:@template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/staffing_templates/1
  #
  # DELETE /admin/staffing_templates/1.json
  ##
  def destroy
   @template = Admin::StaffingTemplate.find(params[:id])
   @template.destroy

    respond_to do |format|
      format.html { redirect_to admin_staffing_templates_url }
      format.json { head :no_content }
    end
  end
end
