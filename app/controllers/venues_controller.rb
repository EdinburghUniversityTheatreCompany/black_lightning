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

  private 
  
  def includes_args
    [image_attachment: :blob]
  end

  def order_args
    ['name']
  end
end
