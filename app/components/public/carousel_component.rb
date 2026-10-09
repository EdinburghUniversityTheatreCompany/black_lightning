class Public::CarouselComponent < ViewComponent::Base
  def initialize(carousel_items:, aspect_ratio: nil)
    @carousel_items = carousel_items
    @aspect_ratio = aspect_ratio
  end
end
