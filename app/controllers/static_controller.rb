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

  # Every static page gets its own, because a page sharing the site-wide boilerplate is a page
  # search engines have to choose between. Hand-written rather than derived from the editable
  # block: these are the eight highest-value non-event pages, and the block bodies read as page
  # content, not as a summary of it.
  PAGE_DESCRIPTIONS = {
    "accessibility"   => "How to find Bedlam Theatre at 11B Bristo Place, Edinburgh EH1 1EZ, and what to expect when you get here: entrances, step-free access and getting around.",
    "black_lightning" => "Project Black Lightning: the open-source Rails application that runs Bedlam Theatre's website, box office admin and members' area.",
    "contact"         => "Get in touch with Bedlam Theatre and the Edinburgh University Theatre Company \u2014 committee contacts, venue hire enquiries and press.",
    "on_fire"         => "Something has gone wrong at Bedlam Theatre. What we know, and who to contact while we put it right.",
    "press"           => "Press and media enquiries for Bedlam Theatre and the Edinburgh University Theatre Company, including images and interview requests.",
    "privacy_policy"  => "How Bedlam Theatre and the Edinburgh University Theatre Company collect, use and store your personal data, and the rights you have over it.",
    "student_theatre" => "What student theatre at Bedlam means: how the EUTC works, who can take part and how to get involved in a production.",
    "welcome_week"    => "New in Edinburgh? What Bedlam Theatre and the EUTC have on during Welcome Week, and how to join in whatever your experience."
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
    @meta[:description] = PAGE_DESCRIPTIONS.fetch(safe_page)

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
