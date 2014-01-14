##
# Public controller for Show. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class ShowsController < ApplicationController

  ##
  # GET /shows
  #
  # GET /shows.json
  ##
  def index
    @shows = Show.current(:order => "start_date ASC").paginate(:page => params[:page], :per_page => 5).all

    @title = "Shows"

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows }
    end
  end

  ##
  # GET /shows/1
  ##
  def show
    # Use ! on find_by to ensure a ActiveRecord::RecordNotFound exception is thrown if the show doesn't exist.
    # This is caught by the application controller to redirect to 404
    @show = Show.find_by_slug!(params[:id])

    @team_members = @show.team_members.all
    @reviews  = @show.reviews.all
    @pictures = @show.pictures.all

    @title = @show.name
    @meta[:description] = @show.description
    @meta["og:image"] = [@base_url + @show.image.url(:medium)] + @pictures.collect{|p| @base_url + p.image.url }

    respond_to do |format|
      format.html
      format.json { render json: @show, methods: [:thumb_image, :slideshow_image], include: [ { pictures: { methods: [:thumb_url, :image_url] } }, team_members: { methods: [:user_name] }] }
    end
  end
end
