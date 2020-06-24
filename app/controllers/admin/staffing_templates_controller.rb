##
# Controller for Admin::StaffingTemplate. More details can be found there.
##
class Admin::StaffingTemplatesController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # GET /admin/staffing_templates/1
  #
  # GET /admin/staffing_templates/1.json
  ##
  def show
    @title = "#{@staffing_template.name} Staffing Template"


    super
  end

  private

  def resource_class
    Admin::StaffingTemplate
  end

  def permitted_params
    [:name, staffing_jobs_attributes: [:id, :_destroy, :name, :user, :user_id]]
  end
end
