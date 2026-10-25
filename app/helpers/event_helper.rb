module EventHelper
  include LinkHelper

  def combine_events_with_carousel_items(events, carousel_items)
    event_carousel_items = events.collect { |event| convert_event_to_carousel_item(event) }

    # Combine the carousel items into one array.
    event_carousel_items + carousel_items
  end

  def convert_event_to_carousel_item(event)
    url = url_for(event)
    {
      title: event.name_and_author,
      tagline: "<small>#{h(event.date_and_price)}</small><br>#{h(event.short_blurb)}".html_safe,
      image: event.fetch_image,
      url: url,
      # nil when pretix is not shown; present? in the carousel handles both nil and missing key
      pretix_slug: event.pretix_shown? ? event.pretix_slug : nil
    }
  end

  # EventsGridComponent items for a member's projects, on their admin and public profiles.
  def team_membership_grid_items(team_memberships)
    team_memberships.map do |team_membership|
      event = team_membership.teamwork
      {
        event: event,
        paragraphs: [
          { content: event.date_range(true), small: true },
          { content: event.short_blurb },
          { content: safe_join([ tag.b("Position"), ": ", team_membership.position ]), class: "mt-auto" }
        ]
      }
    end
  end
end
