class EventsController < ApplicationController
  def find_by_xts_id
    @event = Event.find_by_xts_id(params[:id])

    render json: @event.to_json(methods: [:slideshow_image], include: [pictures: { methods: [:image_url] }])
  end
end
