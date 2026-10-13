# Admin CRUD for departments, whose +match_terms+ suggest a department from a role's position.
class Admin::DepartmentsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [ :name, :ordering, :match_terms ]
  end

  def order_args
    "ordering ASC"
  end
end
