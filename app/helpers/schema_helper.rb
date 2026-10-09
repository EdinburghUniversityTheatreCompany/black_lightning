# JSON-LD structured data. Every method returns a plain Hash; the layout renders whatever
# #schema_documents collects, so a page opts in by having a case here.
module SchemaHelper
  CONTEXT = "https://schema.org".freeze

  ORGANISATION_ID = "/#organisation".freeze
  VENUE_ID = "/#venue".freeze

  VENUE_ADDRESS = {
    "@type" => "PostalAddress",
    "streetAddress" => "11B Bristo Place",
    "addressLocality" => "Edinburgh",
    "postalCode" => "EH1 1EZ",
    "addressCountry" => "GB"
  }.freeze

  SOCIAL_PROFILES = [
    "https://facebook.com/bedlamtheatre.ed",
    "https://instagram.com/eutcbedlamtheatre",
    "https://www.tiktok.com/@eutcbedlamtheatre",
    "https://www.youtube.com/channel/UCXxyhjT8bPvnl1oVAdRJW1Q"
  ].freeze

  EVENT_SCHEDULED = "https://schema.org/EventScheduled".freeze
  EVENT_CANCELLED = "https://schema.org/EventCancelled".freeze
  IN_STOCK = "https://schema.org/InStock".freeze
  SOLD_OUT = "https://schema.org/SoldOut".freeze

  # Amounts in an Event#price string: "£7/£8/£10", "£5 (£4 members)", "Free".
  PRICE_PATTERN = /£\s*(\d+(?:\.\d{1,2})?)/

  # The venue graph is on every page; the rest depend on what the page is.
  def schema_documents
    documents = [ venue_schema ]

    documents << event_schema(@event) if @event.is_a?(Event) && showing?
    documents << news_article_schema(@news) if @news.is_a?(News) && showing?
    documents << item_list_schema if listed_events.present?
    documents << breadcrumb_schema if breadcrumb_trail.length > 1

    documents.compact
  end

  # One graph, so an event's organizer can reference the organisation by @id.
  def venue_schema
    {
      "@context" => CONTEXT,
      "@graph" => [
        {
          "@type" => "PerformingArtsTheater",
          "@id" => absolute_url(VENUE_ID),
          "name" => "Bedlam Theatre",
          "url" => root_url,
          "address" => VENUE_ADDRESS,
          "geo" => { "@type" => "GeoCoordinates", "latitude" => bedlam_latlng[0], "longitude" => bedlam_latlng[1] },
          "sameAs" => SOCIAL_PROFILES,
          "parentOrganization" => { "@id" => absolute_url(ORGANISATION_ID) }
        },
        {
          "@type" => "Organization",
          "@id" => absolute_url(ORGANISATION_ID),
          "name" => "Edinburgh University Theatre Company",
          "alternateName" => "EUTC",
          "url" => root_url,
          "sameAs" => SOCIAL_PROFILES,
          "identifier" => { "@type" => "PropertyValue", "propertyID" => "OSCR", "value" => "SC015800" },
          "location" => { "@id" => absolute_url(VENUE_ID) }
        }
      ]
    }
  end

  # A production, and one node per performance of it.
  #
  # The type comes from the event's SCHEMA_TYPE (TheaterEvent, EducationEvent), never typed in
  # here, or a new subclass would inherit the last one's. Each EventOccurrence is a top-level node
  # with a superEvent back to the run: Google keys rich results off top-level items, so a
  # performance inside subEvent alone would not surface. An event with no occurrences (every
  # archive row) emits a single node with a date-only startDate.
  def event_schema(event)
    return nil if event.start_date.blank?

    performances = event_performance_schemas(event)
    run = event_run_schema(event, performances)

    return run if performances.empty?

    { "@context" => CONTEXT, "@graph" => [ run ] + performances }
  end


  def news_article_schema(news)
    {
      "@context" => CONTEXT,
      "@type" => "NewsArticle",
      "headline" => news.title,
      "url" => news_url(news),
      "datePublished" => news.publish_date&.iso8601,
      "dateModified" => news.updated_at&.iso8601,
      "author" => news.author && { "@type" => "Person", "name" => news.author.name },
      "publisher" => { "@id" => absolute_url(ORGANISATION_ID) },
      "description" => truncate_description(render_plain(news.preview))
    }.compact
  end

  # What a hub page is listing, in order.
  def item_list_schema
    {
      "@context" => CONTEXT,
      "@type" => "ItemList",
      "itemListElement" => listed_events.each_with_index.map do |event, position|
        { "@type" => "ListItem", "position" => position + 1, "name" => event.name, "url" => polymorphic_url(event) }
      end
    }
  end

  def breadcrumb_schema
    {
      "@context" => CONTEXT,
      "@type" => "BreadcrumbList",
      "itemListElement" => breadcrumb_trail.each_with_index.map do |(name, url), position|
        { "@type" => "ListItem", "position" => position + 1, "name" => name, "item" => url }
      end
    }
  end

  # [name, absolute url] pairs, root first, derived from the route.
  def breadcrumb_trail
    trail = [ [ "Home", root_url ] ]

    section = controller&.controller_name.to_s
    return trail if section.blank? || section == "static"

    section_url = safe_url("#{section}_url")
    trail << [ section.titleize, section_url ] if section_url

    trail << [ @title, canonical_url ] if showing? && @title.present?

    trail
  end

  private

  def event_run_schema(event, performances)
    {
      "@context" => CONTEXT,
      "@type" => event.schema_type,
      "@id" => event_schema_id(event),
      "name" => event.name,
      "url" => polymorphic_url(event),
      # Dates, not datetimes: curtain times live on the performance nodes.
      "startDate" => event.start_date.iso8601,
      "endDate" => event.end_date&.iso8601,
      "eventStatus" => EVENT_SCHEDULED,
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "description" => truncate_description(render_plain(event.publicity_text)),
      "image" => event_image_url(event),
      "location" => { "@id" => absolute_url(VENUE_ID) },
      "organizer" => { "@id" => absolute_url(ORGANISATION_ID) },
      "performer" => event_performers(event),
      "workFeatured" => event_work_featured(event),
      "director" => event_crew_person(event, "director"),
      "producer" => event_crew_person(event, "producer"),
      "duration" => event.iso8601_duration,
      "typicalAgeRange" => event.age_guidance.presence,
      "isAccessibleForFree" => event_free(event),
      "offers" => event_offers(event),
      "subEvent" => (performances.map { |node| { "@id" => node["@id"] } } if performances.any?)
    }.compact
  end

  def event_performance_schemas(event)
    return [] unless event.occurrences_are_performances?

    event.event_occurrences.map do |occurrence|
      next nil if occurrence.starts_at.blank?

      {
        "@type" => event.schema_type,
        "@id" => event_schema_id(event, occurrence),
        "name" => event.name,
        "url" => polymorphic_url(event),
        "startDate" => occurrence.starts_at.iso8601,
        "endDate" => occurrence.effective_ends_at&.iso8601,
        "doorTime" => occurrence.doors_open_at&.iso8601,
        "eventStatus" => performance_status(occurrence),
        "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
        "location" => { "@id" => absolute_url(VENUE_ID) },
        "organizer" => { "@id" => absolute_url(ORGANISATION_ID) },
        "accessibilityFeature" => occurrence.schema_accessibility_features.presence,
        "isAccessibleForFree" => event_free(event),
        "offers" => event_offers(event, availability: performance_availability(occurrence)),
        "superEvent" => { "@id" => event_schema_id(event) }
      }.compact
    end.compact
  end

  # A cancelled night is off; a sold-out one is still on. The run's own node stays
  # EventScheduled when one night is cancelled.
  def performance_status(occurrence)
    occurrence.cancelled? ? EVENT_CANCELLED : EVENT_SCHEDULED
  end

  # Cancelled outranks sold out.
  def performance_availability(occurrence)
    return SOLD_OUT if occurrence.cancelled? || occurrence.sold_out?

    IN_STOCK
  end

  def event_schema_id(event, occurrence = nil)
    suffix = occurrence ? "#performance-#{occurrence.id}" : "#event"

    "#{polymorphic_url(event)}#{suffix}"
  end

  # Shows only: on a workshop, Event#author names whoever teaches it, not a playwright.
  def event_work_featured(event)
    return nil unless event.is_a?(Show) && event.author.present?

    { "@type" => "Play", "name" => event.name,
      "author" => { "@type" => "Person", "name" => event.author } }
  end

  # Matched EXACTLY, so "Assistant Director" is not published as the director.
  def event_crew_person(event, role)
    member = event.team_members.find do |candidate|
      candidate.position_segments.any? { |part| part.casecmp?(role) }
    end

    return nil if member&.user.nil?

    { "@type" => "Person", "name" => member.user.name }
  end

  # True when every band is zero, false otherwise. Nil, not false, with no bands: we know nothing.
  def event_free(event)
    prices = event.ticket_prices

    return nil if prices.empty?

    prices.all?(&:free?)
  end

  def showing?
    controller&.action_name == "show"
  end

  # Index actions only, and only collections already loaded for rendering: this must never issue
  # a query of its own.
  def listed_events
    return [] unless controller&.action_name == "index"

    Array(@events || @shows || @workshops || @seasons).grep(Event)
  end

  def event_performers(event)
    performers = event.team_members.select(&:cast?).filter_map { |member| member.user&.name }

    return nil if performers.empty?

    performers.map { |name| { "@type" => "Person", "name" => name } }
  end

  # Structured bands where there are any, each named ("Concession £8"). Scraping Event#price is
  # not legacy cruft: much of the archive has no bands, and those rows have nothing else. A
  # wrong price is a promise the box office must honour, so it only fires when a number is readable.
  def event_offers(event, availability: IN_STOCK)
    prices = event.ticket_prices
    amounts = prices.map(&:amount)
    amounts = event.price.to_s.scan(PRICE_PATTERN).flatten.map(&:to_f) if amounts.empty?

    return nil if amounts.empty?

    url = event_offer_url(event)

    {
      "@type" => "AggregateOffer",
      "priceCurrency" => "GBP",
      "lowPrice" => format("%.2f", amounts.min),
      "highPrice" => format("%.2f", amounts.max),
      "offerCount" => prices.length.nonzero?,
      "availability" => availability,
      "url" => url,
      "offers" => prices.map do |price|
        {
          "@type" => "Offer",
          "name" => price.display_label,
          "price" => format("%.2f", price.amount),
          "priceCurrency" => "GBP",
          "availability" => availability,
          "url" => url
        }
      end.presence
    }.compact
  end

  # Where someone actually buys it.
  def event_offer_url(event)
    event.pretix_shown? ? pretix_event_url(event) : polymorphic_url(event)
  end

  # Reuses @meta["og:image"] (the show page has resolved it) rather than a second
  # Event#slideshow_image_url, whose .processed can generate a variant synchronously mid-render.
  def event_image_url(event)
    from_meta = Array(@meta && @meta["og:image"]).first
    return from_meta if from_meta.present?

    image = event.slideshow_image_url

    image.present? ? absolute_url(image) : nil
  rescue StandardError => e
    # A missing blob must not 500 the page.
    Rails.logger.warn("[SchemaHelper] could not resolve image for event #{event.id}: #{e.message}")
    nil
  end

  def absolute_url(path_or_fragment)
    return path_or_fragment if path_or_fragment.to_s.start_with?("http")

    "#{root_url.chomp('/')}#{path_or_fragment}"
  end

  def safe_url(helper_name)
    return nil unless respond_to?(helper_name)

    public_send(helper_name)
  rescue StandardError
    nil
  end
end
