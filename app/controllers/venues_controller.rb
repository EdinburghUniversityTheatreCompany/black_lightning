##
# Public controller for Venue. More details can be found there.
##
class VenuesController < ApplicationController
  include GenericController

  load_and_authorize_resource

  ##
  # Has include_args
  ##

  ##
  # GET /venues/1
  #
  # GET /venues/1.json
  ##
  def show
    @current_shows = @venue.shows.current.first(3)

    super
  end

  def map
    @title = 'Venues Map'

    @venues_marker_info = Venue.accessible_by(current_ability).map(&:marker_info).compact

    respond_to do |format|
      format.html # map.html.erb
    end
  end

  private 
  
  def includes_args
    [image_attachment: :blob]
  end

  def order_args
    ['name']
  end
end
