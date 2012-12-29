##
# Public controller for Workshop. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class WorkshopsController < ApplicationController

  ##
  # GET /workshops
  #
  # GET /workshops.json
  ##
  def index
    @workshops = Workshop.paginate(:page => params[:page], :per_page => 5).current(:order => "start_date ASC")

    @title = "Workshops"

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @workshops }
    end
  end

  ##
  # GET /workshops/1
  ##
  def show
    # Use ! on find_by to ensure a ActiveRecord::RecordNotFound exception is thrown if the workshop doesn't exist.
    # This is caught by the application controller to redirect to 404
    @workshop = Workshop.find_by_slug!(params[:id])

    @title = @workshop.name
    @meta[:description] = @workshop.description
    @meta["og:image"] = [@base_url + @workshop.image.url(:medium)] + @workshop.pictures.collect{|p| @base_url + p.image.url }

    respond_to do |format|
      format.html
    end
  end
end
