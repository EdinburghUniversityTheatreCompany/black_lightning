##
# Admin controller for Department management.
#
# Departments group opportunity roles; their +match_terms+ drive the auto-suggestion of a
# department from a role's position text.
##
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
