class Public::BasicInfoComponentPreview < ViewComponent::Preview
  def default
    venue = Venue.first!
    render Public::BasicInfoComponent.new(
      header: venue.name,
      image: venue.fetch_image,
      tagline: venue.tagline
    )
  end

  def with_details
    venue = Venue.first!
    render Public::BasicInfoComponent.new(
      header: venue.name,
      image: venue.fetch_image,
      tagline: venue.tagline,
      details: [
        { key: "Address", value: venue.address }
      ]
    )
  end

  def without_tagline
    venue = Venue.first!
    render Public::BasicInfoComponent.new(
      header: venue.name,
      image: venue.fetch_image
    )
  end
end
