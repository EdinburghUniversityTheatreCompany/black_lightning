##
# Admin controller for Fault Reports. More details can be found there.
##

class Admin::FaultReportsController < AdminController
  include GenericController

  load_and_authorize_resource


  ##
  # GET /admin/fault_reports/1
  #
  # GET /admin/fault_reports/1.json
  ##
  def show
    @title = @fault_report.item

    super
  end

  ##
  # POST /admin/fault_reports
  #
  # POST /admin/fault_reports.json
  ##
  def create
    @fault_report.reported_by = current_user if @fault_report.reported_by.nil?

    super
  end

  private

  def includes_args
    [ :reported_by ]
  end

  def order_args
    [ "updated_at DESC" ]
  end

  def permitted_params
    [ :item, :description, :severity, :status, :reported_by_id, :fixed_by_id ]
  end

  def edit_title
    "Edit Fault Report for #{@fault_report.item}"
  end
end
