class EventsController < GenericEventsController
  def find_by_xts_id
    @event = Event.find_by_xts_id(params[:id])

    render json: @event.to_json(methods: [:slideshow_image_url], include: [pictures: { methods: [:display_url] }])
  end

  private

  # Override base_index_database_query because overriding load_index_resources would override @events again. 
  def base_index_database_query
    return super.current
  end
end
