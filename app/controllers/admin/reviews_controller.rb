##
# Admin controller for Venue management.
##
class Admin::ReviewsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [ :title, :url, :body, :rating, :review_date, :organisation, :reviewer, :event_id ]
  end

  def order_args
    [ "review_date DESC" ]
  end
end
