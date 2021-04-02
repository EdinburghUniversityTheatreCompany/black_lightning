##
# Public controller for Workshop. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class WorkshopsController < ApplicationController
  include GenericController

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
    @meta[:description] = helpers.render_plain(@workshop.publicity_text)
    @meta['og:image'] = [@base_url + @workshop.slideshow_image_url] + @workshop.pictures.collect { |p| @base_url + url_for(p.fetch_image) }

    super
  end
end
