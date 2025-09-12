class Admin::MaintenanceAttendancesController < AdminController
  include GenericController
  load_and_authorize_resource

  # INDEX:  /maintenance_attendances
  # SHOW:   /maintenance_attendances/1
  # EDIT:   /maintenance_attendances/1/edit
  # UPDATE: /maintenance_attendances/1
  # NEW:    /maintenance_attendances/new
  # CREATE: /maintenance_attendances

  private

  def permitted_params
    # Make sure that references have _id appended to the end of them.
    # Check existing controllers for inspiration.
    [ :maintenance_session_id, :user_id ]
  end

  def order_args
    [ "date" ]
  end

  def includes_args
    [ :user, :maintenance_session, :maintenance_debt ]
  end
end
