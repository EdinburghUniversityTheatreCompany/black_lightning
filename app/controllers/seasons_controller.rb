class SeasonsController < ApplicationController
  # GET /seasons/1
  def show
    @season = Season.find_by_slug!(params[:id])
  end
end
