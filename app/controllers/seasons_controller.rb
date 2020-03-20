class SeasonsController < ApplicationController
  # GET /seasons/1
  def show
    @season = Season.find_by_slug!(params[:id])
    @events = @season.events.order(:start_date).group_by {|event| l event.start_date, format: :longy }
  end
end
