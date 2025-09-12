##
# Admin controller for Venue management.
##
class Admin::VenuesController < AdminController
  include GenericController

  load_and_authorize_resource

  def map
    @title = "Venues Map"

    @venues_marker_info = Venue.accessible_by(current_ability).map(&:marker_info).compact

    respond_to do |format|
      format.html # map.html.erb
    end
  end

  private

  def permitted_params
    [ :description, :image, :location, :address, :name, :tagline, pictures_attributes: %I[id _destroy description image] ]
  end

  def order_args
    [ "name" ]
  end
end
