class StaticController < ApplicationController
  skip_authorization_check
  
  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show
    begin
      render "static/#{params[:page]}"
    rescue
      Rails.logger.error "Could not find the page at #{request.fullpath}"

      raise(ActionController::RoutingError.new('This page could not be found.'))
    end
  end

  def home
    @news = News.accessible_by(current_ability).includes(image_attachment: :blob).order('publish_date DESC').first(2)
    @events = Event.includes(image_attachment: :blob).current.reorder('start_date ASC')

    @carousel_items = CarouselItem.where(carousel_name: 'Home').active_and_ordered.includes(image_attachment: :blob)
  end
end
