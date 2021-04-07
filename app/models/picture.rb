##
# Represents a picture in the polymorphic association <tt>gallery</tt>
#
# == Schema Information
#
# Table name: pictures
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *description*::        <tt>text(65535)</tt>
# *gallery_id*::         <tt>integer</tt>
# *gallery_type*::       <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Picture < ApplicationRecord
  belongs_to :gallery, polymorphic: true

  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif], attached: true
  validates :access_level, presence: true

  has_and_belongs_to_many :picture_tags, optional: true

  ACCESS_LEVELS = Attachment::ACCESS_LEVELS

  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob('missing.png')) unless image.attached?

    return image
  end

  def gallery_name
    return get_object_name(gallery) if gallery.present?

    return 'No Gallery'
  end

  ##
  # Returns the url of the slideshow image
  ##
  def thumb_url
    return Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.thumb_variant).processed, only_path: true)
  end

  ##
  # Returns the url of the full-size image
  ##
  def display_url
    return Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.square_display_variant).processed, only_path: true)
  end
end
