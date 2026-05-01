class StaticController < ApplicationController
  skip_authorization_check

  ALLOWED_PAGES = %w[accessibility black_lightning contact on_fire press privacy_policy student_theatre welcome_week].freeze

  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show
    page = params[:page]

    safe_page = ALLOWED_PAGES.find { |p| p == page }

    unless safe_page
      Rails.logger.error "Could not find the page at #{request.fullpath}"
      raise ActionController::RoutingError.new("This page could not be found.")
    end

    render "static/#{safe_page}"
  rescue ActionView::MissingTemplate
    Rails.logger.error "Could not find the page at #{request.fullpath}"
    raise ActionController::RoutingError.new("This page could not be found.")
  end

  def home
    @events = Event.includes(image_attachment: :blob).current.reorder("start_date ASC")
    @news = News.where(show_public: true).includes(:author).order("publish_date DESC").current.first(4)

    @carousel_events = @events
    # If there are too many carousel events, filter out workshops, and limit to 3.
    @carousel_events = @carousel_events.where.not(type: "Workshop").first(3)

    @standard_carousel_items = CarouselItem.where(carousel_name: "Home").active_and_ordered.includes(image_attachment: :blob)
  end
end
