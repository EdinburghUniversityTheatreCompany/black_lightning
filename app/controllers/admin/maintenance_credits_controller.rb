class Admin::MaintenanceCreditsController < AdminController
  include GenericController
  load_and_authorize_resource

  # INDEX:  /maintenance_credits
  # SHOW:   /maintenance_credits/1
  # EDIT:   /maintenance_credits/1/edit
  # UPDATE: /maintenance_credits/1
  # NEW:    /maintenance_credits/new
  # CREATE: /maintenance_credits

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
