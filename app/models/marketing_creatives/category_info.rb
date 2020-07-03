# == Schema Information
#
# Table name: marketing_creatives_category_infos
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *profile_id*::  <tt>bigint</tt>
# *category_id*:: <tt>bigint</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class MarketingCreatives::CategoryInfo < ApplicationRecord
  validates :profile, :category, :description, :image, presence: true
  # Validate the uniqueness of the pair of profile and category, so that every profile can only have one entry for each category.
  # TODO: test
  validates_uniqueness_of :category, scope: [:profile]

  #default_scope -> { joins(:profile).order('profile.name ASC') }

  belongs_to :profile, class_name: 'MarketingCreatives::Profile'
  belongs_to :category, class_name: 'MarketingCreatives::Category'

  has_many :pictures, as: :gallery, dependent: :restrict_with_error
  accepts_nested_attributes_for :pictures, allow_destroy: true

  has_one_attached :image
  validates :image, content_type: %i[png jpg jpeg gif]

  ##
  # Display kittens if the image for whatever reason does not exist.
  ##
  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob('missing.png')) unless image.attached? 

    return image
  end
end
