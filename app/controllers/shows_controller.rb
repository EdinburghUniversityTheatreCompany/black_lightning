class ShowsController < ApplicationController
  def index
    @shows = Show.paginate(:page => params[:page], :per_page => 5).current(:order => "start_date ASC")

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows }
    end
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
