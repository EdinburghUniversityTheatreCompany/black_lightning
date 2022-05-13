##
# Admin controller for the picture tags.
##
class Admin::PictureTagsController < AdminController
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
