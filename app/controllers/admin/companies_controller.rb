##
# Admin controller for Company management.
#
# Companies (theatre companies and societies) group opportunities and provide the
# +internal+ flag used to surface EUTC opportunities first.
##
class Admin::CompaniesController < AdminController
  include GenericController

  load_and_authorize_resource

  # Editing a company through the admin counts as reviewing it, clearing the
  # "needs review" prompt on opportunities that reference it.
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
