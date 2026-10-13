# For the few things that are shared between the controllers of the events.

class GenericEventsController < ApplicationController
  include GenericestEventsController

  load_and_authorize_resource find_by: :slug

  def show
    resource_id = get_resource.id
    @event = resource_class.includes(
      :venue,
      :season,
      { team_members: :user },
      { pictures: { image_attachment: :blob } },
      :reviews,
      :video_links,
      { image_attachment: :blob }
    ).find(resource_id)

    # The instance variable load_and_authorize_resource expects.
    instance_variable_set("@#{resource_name.singularize}", @event)

    # Revivals share a name, so a finished run's title carries its year.
    @title = "#{@event.name} (#{@event.end_date.year})" if @event.end_date&.past?

    @meta[:description] = helpers.render_plain(get_resource.publicity_text)
    @meta["og:image"] = [ @base_url + get_resource.slideshow_image_url ] + get_resource.pictures.collect { |p| @base_url + url_for(p.fetch_image) }

    super
  end

  private

  def index_filename
    "/events/index"
  end

  # Every event-type controller renders events/index, so they share its results
  # partial whatever their controller_path.
  def index_results_partial
    "events/index_results"
  end

  def includes_args
    [ image_attachment: :blob ]
  end

  def items_per_page
    15
  end
end
