class ShowsController < ApplicationController
  def index
    @shows = Show.all
  end

  def show
    @show = Show.find_by_slug(params[:id])
    @title = @show.name
    respond_to do |format|
      format.html
    end
  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html)
  end
end
