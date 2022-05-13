##
# Admin controller for the event tags.
##
class Admin::EventTagsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [:name, :description]
  end

  def order_args
    ['name']
  end
end
