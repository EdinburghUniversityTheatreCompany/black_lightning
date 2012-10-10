class ShowsController < ApplicationController
  def index
    @shows = Show.all
  end

  def show
    @show = Show.where(:slug => params[:slug]).first
    respond_to do |format|
      format.html
    end
  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html)
  end
end
