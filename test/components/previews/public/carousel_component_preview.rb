class Public::CarouselComponentPreview < ViewComponent::Preview
  def default
    render Public::CarouselComponent.new(
      carousel_items: sample_items
    )
  end

  def with_aspect_ratio
    render Public::CarouselComponent.new(
      carousel_items: sample_items,
      aspect_ratio: "16/9",
      fit_mode: "cover"
    )
  end

  private

  def sample_items
    CarouselItem.limit(3).map do |item|
      {
        title: item.title,
        tagline: item.tagline,
        image: item,
        url: item.url,
        pretix_slug: item.pretix_slug
      }
    end
  end
end
