# == Schema Information
#
# Table name: marketing_creatives_categories
#
# *id*::              <tt>bigint, not null, primary key</tt>
# *name*::            <tt>string(255)</tt>
# *name_on_profile*:: <tt>string(255)</tt>
# *url*::             <tt>string(255)</tt>
# *created_at*::      <tt>datetime, not null</tt>
# *updated_at*::      <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class MarketingCreatives::Category < ApplicationRecord
  validates :name, :url, :name_on_profile, presence: true, uniqueness: { case_sensitive: true }

  acts_as_url :name

  has_many :category_infos, class_name: "MarketingCreatives::CategoryInfo", dependent: :restrict_with_error
  has_many :profiles, through: :category_infos

  has_one_attached :image
  validates :image, content_type: %i[png jpg jpeg gif]

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
