# The edit form does not include the ability to change the subject or contents.
class Admin::ComplaintsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [:comments, :resolved]
  end

  def order_args
    ['resolved ASC', 'created_at DESC']
  end
end
