class Admin::MaintenanceSessionsController < AdminController
  include GenericController
  load_and_authorize_resource

  # INDEX:  /maintenance_sessions
  # SHOW:   /maintenance_sessions/1
  def show
    @q = @maintenance_session.users.ransack(params[:q], auth_object: current_ability)

    # A user attends (earns a credit) once per attendance, so dedupe for display and show the count.
    @users = @q.result.accessible_by(current_ability).order_by_last_name_first.distinct
    @credit_counts = @maintenance_session.maintenance_attendances.group(:user_id).count

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
    [ :date, :name, maintenance_attendances_attributes: [ :id, :_destroy, :user, :user_id, :quantity ] ]
  end

  def order_args
    [ "date DESC" ]
  end

  def include_class_name_in_show_page_title
    true
  end
end
