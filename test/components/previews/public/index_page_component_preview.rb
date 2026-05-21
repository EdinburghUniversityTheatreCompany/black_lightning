class Public::IndexPageComponentPreview < ViewComponent::Preview
  def default
    render Public::IndexPageComponent.new(
      title: "Venues",
      editable_block_name: "Venues",
      resources: Venue.all,
      items: Venue.limit(3).map do |venue|
        {
          url: "/venues/#{venue.id}",
          image: venue.fetch_image,
          header: venue.name,
          paragraphs: [ { content: venue.tagline } ],
          button_text: "View Details"
        }
      end
    )
  end

  def empty
    render Public::IndexPageComponent.new(
      title: "Venues",
      editable_block_name: "Venues",
      resources: Venue.none,
      items: []
    )
  end
end
