class VenuesController < ApplicationController

  # GET /venues
  # GET /venues.json
  def index
    @venues = Venue.paginate(:page => params[:page], :per_page => 5).all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @venues }
    end
  end

  # GET /venues/1
  # GET /venues/1.json
  def show
    @venue = Venue.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @venue }
    end
  end

end
