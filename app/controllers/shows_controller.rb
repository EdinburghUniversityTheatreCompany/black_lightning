##
# Public controller for Show. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class ShowsController < ApplicationController
  include GenericController

  load_and_authorize_resource find_by: :slug
  ##
  # GET /shows
  #
  # GET /shows.json
  ##
  def index
    @title = 'Shows'

    @events = @shows.includes(image_attachment: :blob)
                    .current
                    .paginate(page: params[:page], per_page: 5)

    respond_to do |format|
      format.html { render '/events/index' }
      format.json { render json: @shows }
    end
  end

  ##
  # GET /shows/1
  ##
  def show
    @meta[:description] = helpers.render_plain(@show.description)
    @meta['og:image'] = [@base_url + @show.slideshow_image_url] + @show.pictures.collect { |p| @base_url + url_for(p.fetch_image) }

    super
  end
end
