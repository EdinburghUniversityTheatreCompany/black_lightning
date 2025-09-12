##
# Admin controller for the event tags.
##
class Admin::EventTagsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [ :name, :ordering, :description ]
  end

  def order_args
    "ordering ASC"
  end
end
