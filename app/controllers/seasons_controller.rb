class SeasonsController < ApplicationController
  def show
    if request.subdomain == 'www' || request.subdomain == '' then
      @season = Season.find_by_slug(params[:id])
    else
      Rails.logger.debug request.subdomain
      @season = Season.find_by_slug(request.subdomain)
    end
  end
end
