##
# Controller for Admin::StaffingTemplate. More details can be found there.
##
class Admin::StaffingTemplatesController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/staffing_templates
  #
  # GET /admin/staffing_templates.json
  ##
  def index
    @title = 'Staffing Templates'
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @staffing_templates }
    end
  end

  ##
  # GET /admin/staffing_templates/1
  #
  # GET /admin/staffing_templates/1.json
  ##
  def show
    @title = "#{@staffing_template.name} Staffing Template"
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @staffing_template.to_json(include: { staffing_jobs: {} }) }
    end
  end

  ##
  # GET /admin/staffing_templates/new
  #
  # GET /admin/staffing_templates/new.json
  ##
  def new
    # Title is set by the view.
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @staffing_template }
    end
  end

  ##
  # GET /admin/staffing_templates/1/edit
  ##
  def edit
    # Title is set by the view.
  end

  ##
  # POST /admin/staffing_templates
  #
  # POST /admin/staffing_templates.json
  ##
  def create
    #@staffing_template = Admin::StaffingTemplate.new(staffing_template_params)

    respond_to do |format|
      if @staffing_template.save
        flash[:success] = 'Staffing template was successfully created.'
        format.html { redirect_to admin_staffing_template_path(@staffing_template) }
        format.json { render json: @staffing_template, status: :created, location: @staffing_template }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @staffing_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/staffing_templates/1
  #
  # PUT /admin/staffing_templates/1.json
  ##
  def update
    respond_to do |format|
      if @staffing_template.update(staffing_template_params)
        flash[:success] = 'Staffing template was successfully updated.'
        format.html { redirect_to admin_staffing_template_path(@staffing_template) }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @staffing_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/staffing_templates/1
  #
  # DELETE /admin/staffing_templates/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@staffing_template)

    respond_to do |format|
      format.html { redirect_to admin_staffing_templates_url }
      format.json { head :no_content }
    end
  end

  private

  def staffing_template_params
    params.require(:admin_staffing_template).permit(:name,
                                                    staffing_jobs_attributes: [:id, :_destroy, :name, :user, :user_id])
  end
end
