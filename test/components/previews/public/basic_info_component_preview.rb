class Public::BasicInfoComponentPreview < ViewComponent::Preview
  def default
    info(tagline: venue.tagline)
  end

  def with_details
    info(tagline: venue.tagline, details: [ { key: "Address", value: venue.address } ])
  end

  def without_tagline
    info
  end

  private

  def venue = @venue ||= Venue.first!

  def info(**extra)
    render Public::BasicInfoComponent.new(header: venue.name, image: venue.fetch_image, **extra)
  end
end
