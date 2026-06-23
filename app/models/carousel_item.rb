# == Schema Information
#
# Table name: carousel_items
# Database name: primary
#
#  id            :bigint           not null, primary key
#  carousel_name :string(255)
#  is_active     :boolean
#  ordering      :integer
#  tagline       :text(16777215)
#  title         :string(255)
#  url           :string(255)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_carousel_items_on_is_active_and_ordering  (is_active,ordering)
#
class CarouselItem < ApplicationRecord
  CAROUSEL_NAMES = [ "Home" ].freeze

  CAROUSEL_CONFIG = {
    "Home" => { aspect_ratio: [ 960, 500 ], fit_mode: "cover" }
  }.freeze

  validates :title, :tagline, :carousel_name, :ordering, presence: true
  validates :carousel_name, inclusion: { in: CAROUSEL_NAMES }
  validates :image, attached: true

  has_one_attached :image

  normalizes :title, :tagline, with: ->(value) { value&.strip }

  def self.active_and_ordered
    where(is_active: true).order("ordering")
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[carousel_name is_active ordering tagline title url]
  end
end
