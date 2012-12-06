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
    # Use ! on find_by to ensure a ActiveRecord::RecordNotFound exception is thrown if the show doesn't exist.
    # This is caught by the application controller to redirect to 404
    @show = Show.find_by_slug!(params[:id])

    @title = @show.name
    @meta[:description] = @show.description
    @meta["og:image"] = [@base_url + @show.image.url(:medium)] + @show.pictures.collect{|p| @base_url + p.image.url }

    respond_to do |format|
      format.html
    end
  end
end
