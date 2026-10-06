##
# Admin controller for Company management.
##
class Admin::CompaniesController < AdminController
  include GenericController

  load_and_authorize_resource

  # Saving through the admin counts as reviewing, which clears the "needs review" prompt.
  def create
    @company.reviewed = true
    super
  end

  def update
    @company.reviewed = true
    super
  end

  private

  def permitted_params
    [ :name, :internal, :website, :instagram ]
  end

  def order_args
    [ "internal DESC", "name ASC" ]
  end
end
