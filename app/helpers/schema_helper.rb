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
  # A production. TheaterEvent rather than Event: it is the specific type Google understands for
  # a staged performance.
  ##
  def event_schema(event)
    return nil if event.start_date.blank?

    {
      "@context" => CONTEXT,
      "@type" => "TheaterEvent",
      "name" => event.name,
      "url" => polymorphic_url(event),
      # Dates, not datetimes. The schema carries no curtain times, so a date-only startDate is
      # the honest answer; Google renders an event result from it and wants a time for the
      # richest one. See the note in CLAUDE.md about adding performances.
      "startDate" => event.start_date.iso8601,
      "endDate" => event.end_date&.iso8601,
      "eventStatus" => "https://schema.org/EventScheduled",
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "description" => truncate_description(render_plain(event.publicity_text)),
      "image" => event_image_url(event),
      "location" => { "@id" => absolute_url(VENUE_ID) },
      "organizer" => { "@id" => absolute_url(ORGANISATION_ID) },
      "performer" => event_performers(event),
      "offers" => event_offers(event)
    }.compact
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
  # Event#price is free text ("£7/£8/£10", "£5 (£4 members)", "Free"), so offers are emitted only
  # when a number can actually be read out of it. A wrong price in a rich result is worse than no
  # price -- it is a promise the box office has to honour.
  ##
  def event_offers(event)
    amounts = event.price.to_s.scan(PRICE_PATTERN).flatten.map(&:to_f).sort

    return nil if amounts.empty?

    {
      "@type" => "AggregateOffer",
      "priceCurrency" => "GBP",
      "lowPrice" => format("%.2f", amounts.first),
      "highPrice" => format("%.2f", amounts.last),
      "availability" => "https://schema.org/InStock",
      "url" => event.pretix_shown? ? pretix_event_url(event) : polymorphic_url(event)
    }
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
