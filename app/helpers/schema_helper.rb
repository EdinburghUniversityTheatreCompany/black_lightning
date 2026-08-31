##
# JSON-LD structured data.
#
# Google's event rich results and the "Things to do" surfaces are fed almost entirely by Event
# markup, which is why a ticketed venue needs this at all.
#
# Every method returns a plain Hash. The layout renders whatever #schema_documents collects, so a
# page opts in by having a case here rather than by remembering to call something.
##
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

  # Amounts in an Event#price string: "£7/£8/£10", "£5 (£4 members)", "Free".
  # schema.org vocabulary, named once rather than repeated as literals across
  # the run node, the performance nodes and both offer builders.
  EVENT_SCHEDULED = "https://schema.org/EventScheduled".freeze
  EVENT_CANCELLED = "https://schema.org/EventCancelled".freeze
  IN_STOCK = "https://schema.org/InStock".freeze
  SOLD_OUT = "https://schema.org/SoldOut".freeze

  PRICE_PATTERN = /£\s*(\d+(?:\.\d{1,2})?)/

  ##
  # Every JSON-LD document this page should carry. The venue graph is on every page; the rest
  # depend on what the page is.
  ##
  def schema_documents
    documents = [ venue_schema ]

    documents << event_schema(@event) if @event.is_a?(Event) && showing?
    documents << news_article_schema(@news) if @news.is_a?(News) && showing?
    documents << item_list_schema if listed_events.present?
    documents << breadcrumb_schema if breadcrumb_trail.length > 1

    documents.compact
  end

  ##
  # The theatre itself, and the company that runs it. One graph rather than two documents so the
  # organisation can be referenced by @id from an event's organizer without repeating it.
  ##
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
          # The charity number is already printed in the footer; it is the strongest identity
          # signal this organisation has.
          "identifier" => { "@type" => "PropertyValue", "propertyID" => "OSCR", "value" => "SC015800" },
          "location" => { "@id" => absolute_url(VENUE_ID) }
        }
      ]
    }
  end

  ##
  # A production, and one node per performance of it.
  #
  # TheaterEvent rather than Event: it is the specific type Google understands for a staged
  # performance. Each EventOccurrence becomes a TheaterEvent of its OWN, at the top level of the
  # graph with a superEvent pointing back at the run -- Google keys its rich results off top-level
  # items, so a performance buried in subEvent alone would not surface, while the two-way link
  # still says these are one production rather than N unrelated shows.
  #
  # An event with no occurrences -- every one of the ~3000 archive rows -- emits exactly what it
  # emitted before: a single node with a date-only startDate.
  ##
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

  ##
  # What a hub page is listing, in order. Gives Google the productions on /events and /shows as a
  # set rather than as whatever it can infer from the markup.
  ##
  def item_list_schema
    {
      "@context" => CONTEXT,
      "@type" => "ItemList",
      "itemListElement" => listed_events.each_with_index.map do |event, position|
        { "@type" => "ListItem", "position" => position + 1, "name" => event.name, "url" => polymorphic_url(event) }
      end
    }
  end

  ##
  # The archive is 164 pages deep, so a breadcrumb is how that hierarchy reaches a result page.
  ##
  def breadcrumb_schema
    {
      "@context" => CONTEXT,
      "@type" => "BreadcrumbList",
      "itemListElement" => breadcrumb_trail.each_with_index.map do |(name, url), position|
        { "@type" => "ListItem", "position" => position + 1, "name" => name, "item" => url }
      end
    }
  end

  ##
  # [name, absolute url] pairs, root first. Derived from the route rather than declared per page,
  # so a new listing page gets a trail without remembering to build one.
  ##
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
      "@type" => "TheaterEvent",
      "@id" => event_schema_id(event),
      "name" => event.name,
      "url" => polymorphic_url(event),
      # Dates, not datetimes, for the run as a whole: it spans days. The curtain times live on the
      # performance nodes below.
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

  ##
  # One node per performance, each carrying the thing the run cannot: a real curtain time.
  ##
  def event_performance_schemas(event)
    return [] unless event.respond_to?(:event_occurrences)
    return [] unless event.occurrences_are_performances?

    event.event_occurrences.map do |occurrence|
      next nil if occurrence.starts_at.blank?

      {
        "@type" => "TheaterEvent",
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

  # A cancelled night is off; a sold-out one is still happening. Only the run's
  # own node stays EventScheduled regardless -- one cancelled performance does
  # not cancel the run.
  def performance_status(occurrence)
    occurrence.cancelled? ? EVENT_CANCELLED : EVENT_SCHEDULED
  end

  # A ticket link to a night nobody can buy into is worse than no rich result.
  # Cancelled outranks sold out, as it does in the on-page exception lines.
  def performance_availability(occurrence)
    return SOLD_OUT if occurrence.cancelled? || occurrence.sold_out?

    IN_STOCK
  end

  def event_schema_id(event, occurrence = nil)
    suffix = occurrence ? "#performance-#{occurrence.id}" : "#event"

    "#{polymorphic_url(event)}#{suffix}"
  end

  ##
  # The play, and who wrote it. Shows only: a workshop is not a play, and Event#author on one names
  # whoever is running it rather than a playwright.
  ##
  def event_work_featured(event)
    return nil unless event.is_a?(Show) && event.author.present?

    { "@type" => "Play", "name" => event.name,
      "author" => { "@type" => "Person", "name" => event.author } }
  end

  ##
  # A crew credit matched EXACTLY, so "Assistant Director" is not published as the director. Team
  # positions are free text split on "/", the same way TeamMember reads them.
  ##
  def event_crew_person(event, role)
    return nil unless event.respond_to?(:team_members)

    member = event.team_members.find do |candidate|
      candidate.position_segments.any? { |part| part.casecmp?(role) }
    end

    return nil if member&.user.nil?

    { "@type" => "Person", "name" => member.user.name }
  end

  # True only when every band is zero, and FALSE when they are not -- a paid event saying so is
  # worth stating. Nil only when there are no bands at all: we do not know it is paid, we just have
  # nothing structured to say.
  def event_free(event)
    prices = event.ticket_prices

    return nil if prices.empty?

    prices.all?(&:free?)
  end

  def showing?
    controller&.action_name == "show"
  end

  ##
  # The events a hub page is listing. Only on index actions, and only for collections already
  # loaded for rendering -- this must never issue a query of its own for a script tag.
  ##
  def listed_events
    return [] unless controller&.action_name == "index"

    collection = @events || @shows || @workshops || @seasons

    return [] unless collection.respond_to?(:to_a)

    collection.to_a.select { |item| item.is_a?(Event) }
  end

  def event_performers(event)
    return nil unless event.respond_to?(:team_members)

    performers = event.team_members.select(&:cast?).filter_map { |member| member.user&.name }

    return nil if performers.empty?

    performers.map { |name| { "@type" => "Person", "name" => name } }
  end

  ##
  # Structured bands where there are any, and each one named -- "Concession £8" is a far better
  # rich result than a bare range.
  #
  # Falling back to scraping Event#price is not legacy cruft: the parser refused about 38% of the
  # archive outright, and those rows have nothing else to offer. A wrong price in a rich result is
  # worse than no price -- it is a promise the box office has to honour -- so the scrape still only
  # fires when a number can actually be read out.
  ##
  def event_offers(event, availability: IN_STOCK)
    structured = event.ticket_prices

    return structured_offers(event, structured, availability) if structured.any?

    scraped_offers(event, availability)
  end

  def structured_offers(event, prices, availability = IN_STOCK)
    amounts = prices.map(&:amount).sort

    {
      "@type" => "AggregateOffer",
      "priceCurrency" => "GBP",
      "lowPrice" => format("%.2f", amounts.first),
      "highPrice" => format("%.2f", amounts.last),
      "offerCount" => prices.length,
      "availability" => availability,
      "url" => event_offer_url(event),
      "offers" => prices.map do |price|
        {
          "@type" => "Offer",
          "name" => price.display_label,
          "price" => format("%.2f", price.amount),
          "priceCurrency" => "GBP",
          "availability" => availability,
          "url" => event_offer_url(event)
        }
      end
    }
  end

  def scraped_offers(event, availability = IN_STOCK)
    amounts = event.price.to_s.scan(PRICE_PATTERN).flatten.map(&:to_f).sort

    return nil if amounts.empty?

    {
      "@type" => "AggregateOffer",
      "priceCurrency" => "GBP",
      "lowPrice" => format("%.2f", amounts.first),
      "highPrice" => format("%.2f", amounts.last),
      "availability" => availability,
      "url" => event_offer_url(event)
    }
  end

  # Where someone actually buys it.
  def event_offer_url(event)
    event.pretix_shown? ? pretix_event_url(event) : polymorphic_url(event)
  end

  ##
  # The show page has already resolved this into @meta["og:image"] (an array: the banner plus
  # every production photo). Reusing it avoids a second Event#slideshow_image_url, which calls
  # .processed and so can generate the variant synchronously mid-render.
  ##
  def event_image_url(event)
    from_meta = Array(@meta && @meta["og:image"]).first
    return from_meta if from_meta.present?

    image = event.slideshow_image_url

    image.present? ? absolute_url(image) : nil
  rescue StandardError => e
    # A blob missing from storage must not take the whole page down for a script tag.
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
