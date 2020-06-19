##
# Public controller for Workshop. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class WorkshopsController < ApplicationController
  load_and_authorize_resource find_by: :slug
  ##
  # GET /workshops
  #
  # GET /workshops.json
  ##
  def index
    @events = @workshops.includes(image_attachment: :blob)
                        .paginate(page: params[:page], per_page: 10)
                        .current
                        .order('start_date ASC')

    @title = 'Workshops'

    respond_to do |format|
      format.html { render '/events/index' }
      format.json { render json: @workshops }
    end
  end

  ##
  # GET /workshops/1
  ##
  def show
    @title = @workshop.name
    @meta[:description] = helpers.render_plain(@workshop.description)

    @meta['og:image'] = [@base_url + @workshop.slideshow_image_url] + @workshop.pictures.collect { |p| @base_url + url_for(p.fetch_image) }

    respond_to do |format|
      format.html
    end
  end
end
