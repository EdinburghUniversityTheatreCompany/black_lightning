module EventHelper
  include LinkHelper

  def combine_events_with_carousel_items(events, carousel_items)
    event_carousel_items = events.collect { |event| convert_event_to_carousel_item(event) }
    
    # Combine the carousel items into one array.
    return event_carousel_items + carousel_items
  end

  def convert_event_to_carousel_item(event)
    url = url_for(event)
    {
      title: event.name_and_author,
      tagline: "<small>#{event.date_and_price}</small><br>#{event.short_blurb}".html_safe,
      image: event.fetch_image,
      url: url
    }
  end
end
