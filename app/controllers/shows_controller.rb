##
# Public controller for Show. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class ShowsController < ApplicationController
  load_and_authorize_resource find_by: :slug
  ##
  # GET /shows
  #
  # GET /shows.json
  ##
  def index
    @title = 'Shows'

    @events = @shows.current.paginate(page: params[:page], per_page: 5)

    respond_to do |format|
      format.html { render '/events/index' }
      format.json { render json: @shows }
    end
  end

  ##
  # GET /shows/1
  ##
  def show
    @title = @show.name
    @meta[:description] = @show.description
    @meta['og:image'] = [@base_url + @show.slideshow_image_url] + @show.pictures.collect { |p| @base_url + p.image.url }

    respond_to do |format|
      format.html
      format.json { render json: @show, methods: [:thumb_image_url, :slideshow_image_url], include: [{ pictures: { methods: [:thumb_url, :image_url] } }, team_members: { methods: [:user_name] }] }
    end
  end
end
