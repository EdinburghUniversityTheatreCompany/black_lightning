class SeasonsController < ApplicationController
  include GenericController

  load_and_authorize_resource find_by: :slug

  # GET /seasons/
  def index
    @events = @seasons.includes(image_attachment: :blob)
                      .paginate(page: params[:page], per_page: 10)
                      .current

    respond_to do |format|
      format.html { render '/events/index' }
      format.json { render json: @workshops }
    end
  end

  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    @meta[:description] = helpers.render_plain(@season.publicity_text)

    @meta['og:image'] = [@base_url + @season.slideshow_image_url] + @season.pictures.collect { |p| @base_url + url_for(p.fetch_image) }
    super
  end
end
