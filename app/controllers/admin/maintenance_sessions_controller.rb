class Admin::MaintenanceSessionsController < AdminController
  include GenericController
  load_and_authorize_resource 

  # INDEX:  /maintenance_sessions
  # SHOW:   /maintenance_sessions/1
  def show
    @q = @maintenance_session.users.ransack(params[:q], auth_object: current_ability)

    @users = @q.result.accessible_by(current_ability)

    super
  end

  # EDIT:   /maintenance_sessions/1/edit
  # UPDATE: /maintenance_sessions/1
  # NEW:    /maintenance_sessions/new
  # CREATE: /maintenance_sessions

  private

  def permitted_params
    # Make sure that references have _id appended to the end of them.
    # Check existing controllers for inspiration.
    [:date, maintenance_attendances_attributes: [:id, :_destroy, :user, :user_id]]
  end

  def order_args
    ['date DESC']
  end

  def include_class_name_in_show_page_title
    true
  end
end
