class StaticController < ApplicationController
  skip_authorization_check

  # slug => the name the page goes by. Without these every one of them rendered
  # <title>Bedlam Theatre</title>, including the Find Us page, which is the landing page for
  # every "theatre near me" search.
  PAGE_TITLES = {
    "accessibility"   => "Accessibility & Find Us",
    "black_lightning" => "Project Black Lightning",
    "contact"         => "Contact Us",
    "on_fire"         => "On Fire",
    "press"           => "Press",
    "privacy_policy"  => "Privacy Policy",
    "student_theatre" => "Student Theatre",
    "welcome_week"    => "Welcome Week"
  }.freeze

  ALLOWED_PAGES = PAGE_TITLES.keys.freeze

  # Only where the page has a specific job to do in search. The rest keep the site description,
  # which describes them accurately enough.
  PAGE_DESCRIPTIONS = {
    "accessibility"   => "How to find Bedlam Theatre at 11B Bristo Place, Edinburgh EH1 1EZ, and what to expect when you get here: entrances, step-free access and getting around.",
    "contact"         => "Get in touch with Bedlam Theatre and the Edinburgh University Theatre Company \u2014 committee contacts, venue hire enquiries and press.",
    "student_theatre" => "What student theatre at Bedlam means: how the EUTC works, who can take part and how to get involved in a production."
  }.freeze

  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show
    page = params[:page]

    safe_page = ALLOWED_PAGES.find { |p| p == page }

    unless safe_page
      Rails.logger.error "Could not find the page at #{request.fullpath}"
      raise ActionController::RoutingError.new("This page could not be found.")
    end

    @title = PAGE_TITLES.fetch(safe_page)
    @meta[:description] = PAGE_DESCRIPTIONS[safe_page] if PAGE_DESCRIPTIONS.key?(safe_page)

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

    @home_opportunities = Opportunity.active.includes(:company, :roles).limit(5)
  end
end
