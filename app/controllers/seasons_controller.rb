class SeasonsController < ApplicationController
  def show
    @season = Season.find_by_slug!(params[:id])
    @team_members = @season.team_members
  end
end
