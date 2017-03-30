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
    @fault_reports = FaultReport.paginate(page: params[:page], per_page: 15).order('updated_at DESC')

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
    @fault_report = FaultReport.find(params[:id])
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
    @fault_report = FaultReport.new
    @title = 'Create Fault Report'
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @fault_report }
    end
  end

  ##
  # GET /admin/fault_reports/1/edit
  ##
  def edit
    @fault_report = FaultReport.find(params[:id])
    @title = "Edit #{@fault_report.item}"
  end

  ##
  # POST /admin/fault_reports
  #
  # POST /admin/fault_reports.json
  ##
  def create
    @fault_report = FaultReport.new(params[:fault_report])
    @fault_report.reported_by = current_user

    respond_to do |format|
      if @fault_report.save
        format.html { redirect_to [:admin, @fault_report], notice: 'Fault Report was successfully created.' }
        format.json { render json: [:admin, @fault_report], status: :created, location: @fault_report }
      else
        format.html { render 'new' }
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
    @fault_report = FaultReport.find(params[:id])

    respond_to do |format|
      if @fault_report.update_attributes(params[:fault_report])
        format.html { redirect_to [:admin, @fault_report], notice: 'Fault Report was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
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
    @fault_report = FaultReport.find(params[:id])
    @fault_report.destroy

    respond_to do |format|
      format.html { redirect_to admin_fault_reports_index_url }
      format.json { head :no_content }
    end
  end
end
