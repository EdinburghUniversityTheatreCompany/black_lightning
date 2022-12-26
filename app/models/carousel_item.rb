class CarouselItem < ApplicationRecord
  validates :title, :tagline, :carousel_name, :ordering, presence: true
  validates :image, attached: true

  has_one_attached :image

  CAROUSEL_NAMES = ['Home'].freeze

  def self.active_and_ordered
    return where(is_active: true).order('ordering')
  end
end
