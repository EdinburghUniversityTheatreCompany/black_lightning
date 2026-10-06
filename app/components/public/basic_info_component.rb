class Public::BasicInfoComponent < ViewComponent::Base
  def initialize(header:, image:, details: [], tagline: nil, admin_site: false)
    @header = header
    @image = image
    @details = details
    @tagline = tagline
    @admin_site = admin_site
  end

  private

  def any_details?
    @details.any?
  end

  def show_card_body?
    @tagline.present? || @admin_site
  end
end
