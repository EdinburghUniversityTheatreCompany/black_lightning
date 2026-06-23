# == Schema Information
#
# Table name: marketing_creatives_category_infos
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text(16777215)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  category_id :bigint
#  profile_id  :bigint
#
# Indexes
#
#  index_marketing_creatives_category_infos_on_category_id  (category_id)
#  index_marketing_creatives_category_infos_on_profile_id   (profile_id)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => marketing_creatives_categories.id)
#  fk_rails_...  (profile_id => marketing_creatives_profiles.id)
#
class MarketingCreatives::CategoryInfo < ApplicationRecord
  validates :profile, :category, :image, presence: true

  # Validate the uniqueness of the pair of profile and category, so that every profile can only have one entry for each category.
  validates_uniqueness_of :category, scope: [ :profile ]

  # default_scope -> { joins(:profile).order('profile.name ASC') }

  belongs_to :profile, class_name: "MarketingCreatives::Profile"
  belongs_to :category, class_name: "MarketingCreatives::Category"

  has_many :pictures, as: :gallery, dependent: :restrict_with_error
  accepts_nested_attributes_for :pictures, allow_destroy: true

  has_one_attached :image
  validates :image, content_type: %i[png jpg jpeg gif webp]

  def self.ransackable_attributes(auth_object = nil)
    %w[profile_id category_id description]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[profile category]
  end

  ##
  # Display kittens if the image for whatever reason does not exist.
  ##
  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob("missing.png")) unless image.attached?

    image
  end
end
