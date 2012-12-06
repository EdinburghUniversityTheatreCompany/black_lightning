class ShowsController < ApplicationController
  def index
    @shows = Show.paginate(:page => params[:page], :per_page => 5).current(:order => "start_date ASC")

    @title = "Shows"

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows }
    end
  end

  def show
    @show = Show.find_by_slug(params[:id])

    if @show.nil? then
      raise ActionController::RoutingError.new('Not Found')
    end

    @title = @show.name
    @meta[:description] = @show.description
    @meta["og:image"] = [@base_url + @show.image.url(:medium)] + @show.pictures.collect{|p| @base_url + p.image.url }

    respond_to do |format|
      format.html
    end
  end
end
