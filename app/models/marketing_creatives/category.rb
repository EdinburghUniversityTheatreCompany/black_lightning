# == Schema Information
#
# Table name: marketing_creatives_categories
# Database name: primary
#
#  id              :bigint           not null, primary key
#  name            :string(255)
#  name_on_profile :string(255)
#  url             :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_marketing_creatives_categories_on_url  (url)
#
class MarketingCreatives::Category < ApplicationRecord
  validates :name, :url, :name_on_profile, presence: true, uniqueness: { case_sensitive: true }

  acts_as_url :name

  has_many :category_infos, class_name: "MarketingCreatives::CategoryInfo", dependent: :restrict_with_error
  has_many :profiles, through: :category_infos

  has_one_attached :image
  validates :image, content_type: %i[png jpg jpeg gif webp]

  normalizes :name, with: ->(name) { name&.strip }

  def to_param
    url
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name name_on_profile url]
  end

  ##
  # Display kittens if the image for whatever reason does not exist.
  ##
  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob("missing.png")) unless image.attached?

    image
  end
end
