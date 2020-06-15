##
# Public controller for Venue. More details can be found there.
##
class VenuesController < ApplicationController
  load_and_authorize_resource
  ##
  # GET /venues
  #
  # GET /venues.json
  ##
  def index
    @title = 'Venues'
    @venues = @venues.includes(image_attachment: :blob).paginate(page: params[:page], per_page: 20)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @venues }
    end
  end

  ##
  # GET /venues/1
  #
  # GET /venues/1.json
  ##
  def show
    @title = @venue.name

    @current_shows = @venue.shows.current.first(3)

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @venue }
    end
  end
end
