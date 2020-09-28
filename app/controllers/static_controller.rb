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
    @shows = Show.includes(image_attachment: :blob).current.order('start_date ASC')
    @last_show = Show.last_event
  end
end
