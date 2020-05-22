##
# Admin controller for Fault Reports. More details can be found there.
##

class Admin::FaultReportsController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/fault_reports
  #
  # GET /admin/fault_reports.json
  ##
  def index
    @title = 'Fault Reports'
    @fault_reports = @fault_reports.includes(:reported_by)
                                   .order('updated_at DESC')
                                   .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @fault_reports }
    end
  end

  ##
  # GET /admin/fault_reports/1
  #
  # GET /admin/fault_reports/1.json
  ##
  def show
    @title = @fault_report.item
    respond_to do |format|
      format.html
      format.json { render json: @fault_report }
    end
  end

  ##
  # GET /admin/fault_reports/new
  #
  # GET /admin/fault_reports/new.json
  ##
  def new
    # The title is set by the view.
    
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @fault_report }
    end
  end

  ##
  # GET /admin/fault_reports/1/edit
  ##
  def edit
    # The title is set by the view.
  end

  ##
  # POST /admin/fault_reports
  #
  # POST /admin/fault_reports.json
  ##
  def create
    @fault_report.reported_by = current_user unless params[:fault_report][:reported_by_id]

    respond_to do |format|
      if @fault_report.save
        format.html { redirect_to [:admin, @fault_report], notice: 'Fault Report was successfully created.' }
        format.json { render json: [:admin, @fault_report], status: :created, location: @fault_report }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @fault_report.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/fault_reports/1
  #
  # PUT /admin/fault_reports/1.json
  ##
  def update
    respond_to do |format|
      if @fault_report.update(fault_report_params)
        format.html { redirect_to [:admin, @fault_report], notice: 'Fault Report was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @fault_report.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/fault_reports/1
  #
  # DELETE /admin/fault_reports/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@fault_report)

    respond_to do |format|
      format.html { redirect_to admin_fault_reports_path }
      format.json { head :no_content }
    end
  end

  private

  def fault_report_params
    params.require(:fault_report).permit(:item, :description, :severity, :status, :reported_by_id, :fixed_by_id)
  end
end
