##
# Admin controller for the attachment tags.
##
class Admin::AttachmentTagsController < AdminController
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
