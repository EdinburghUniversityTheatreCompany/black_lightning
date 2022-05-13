##
# Admin controller for Venue management.
##
class Admin::VenuesController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def permitted_params
    [:description, :image, :location, :name, :tagline, pictures_attributes: %I[id _destroy description image]]
  end

  def order_args
    ['name']
  end
end
