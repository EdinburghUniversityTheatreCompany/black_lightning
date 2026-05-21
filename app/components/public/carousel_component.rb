class Public::CarouselComponent < ViewComponent::Base
  def initialize(carousel_items:, aspect_ratio: nil, fit_mode: "cover")
    @carousel_items = carousel_items
    @aspect_ratio = aspect_ratio
    @fit_mode = fit_mode
  end
end
