class EventsController < ApplicationController
  def find_by_xts_id
    @event = Event.find_by_xts_id(params[:id])

    render json: @event.to_json(methods: [:slideshow_image_url], include: [pictures: { methods: [:display_url] }])
  end
end
