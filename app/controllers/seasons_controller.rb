class SeasonsController < ApplicationController
  load_and_authorize_resource find_by: :slug

  # GET /seasons/
  def index
    @events = @seasons.paginate(page: params[:page], per_page: 10).current

    @title = 'Seasons'

    respond_to do |format|
      format.html { render '/events/index' }
      format.json { render json: @workshops }
    end
  end

  # GET /seasons/1
  def show
    @title = @season.name
    @events = @season.events.unscoped.order(:start_date).group_by { |event| l event.start_date, format: :longy }
  end
end
