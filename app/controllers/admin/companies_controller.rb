##
# Admin controller for Company management.
#
# Companies (theatre companies and societies) group opportunities and provide the
# +internal+ flag used to surface EUTC opportunities first.
##
class Admin::CompaniesController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [ :name, :internal, :website ]
  end

  def order_args
    [ "internal DESC", "name ASC" ]
  end
end
