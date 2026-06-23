##
# Represents a picture in the polymorphic association <tt>gallery</tt>
#
# == Schema Information
#
# Table name: pictures
# Database name: primary
#
#  id                 :integer          not null, primary key
#  access_level       :integer          default(2), not null
#  description        :text(16777215)
#  gallery_type       :string(255)
#  image_content_type :string(255)
#  image_file_name    :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  gallery_id         :integer
#
# Indexes
#
#  index_pictures_on_gallery_id                   (gallery_id)
#  index_pictures_on_gallery_type                 (gallery_type)
#  index_pictures_on_gallery_type_and_gallery_id  (gallery_type,gallery_id)
#
class Picture < ApplicationRecord
  include NameHelper

  belongs_to :gallery, polymorphic: true

  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif webp], attached: true
  validates :access_level, presence: true

  has_and_belongs_to_many :picture_tags, optional: true

  ACCESS_LEVELS = Attachment::ACCESS_LEVELS

  def self.include_images
    self.includes({ image_attachment: :blob })
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[access_level description gallery_id gallery_type]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[gallery image_attachment image_blob picture_tags]
  end

  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob("missing.png")) unless image.attached?

    image
  end

  def authorizable_item
    gallery
  end

  def gallery_name
    return get_object_name(gallery) if gallery.present?

    "No Gallery"
  end

  def filename
    fetch_image.blob.filename
  end

  ##
  # Returns the url of the slideshow image
  ##
  def thumb_url
    Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.thumb_variant).processed, only_path: true)
  end

  ##
  # Returns the url of the full-size image
  ##
  def display_url
    Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.square_display_variant).processed, only_path: true)
  end
end
