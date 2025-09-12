# For the few things that are shared between the controllers of the events.

class GenericEventsController < ApplicationController
  include GenericestEventsController

  load_and_authorize_resource find_by: :slug

  def show
    @meta[:description] = helpers.render_plain(get_resource.publicity_text)
    @meta["og:image"] = [ @base_url + get_resource.slideshow_image_url ] + get_resource.pictures.collect { |p| @base_url + url_for(p.fetch_image) }

    super
  end

  private

  def index_filename
    "/events/index"
  end

  def includes_args
    [ image_attachment: :blob ]
  end

  def items_per_page
    15
  end
end
