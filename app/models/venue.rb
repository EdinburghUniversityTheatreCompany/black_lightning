##
# Represents a venue.
#
# Note that while urls are generated to include the slug, like Show, they also include the id.
#
# Therefore, unlike Show, it is NOT necessary to search for the venue by slug - using <tt>find</tt> will work perfectly well.
#
# == Schema Information
#
# Table name: venues
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *description*::        <tt>text(65535)</tt>
# *location*::           <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Venue < ApplicationRecord
  include FormattingHelper

  validates :name, :description, presence: true

  has_many :shows
  has_many :pictures, as: :gallery

  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true

  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif]

  normalizes :email, with: ->(email) { email&.downcase&.strip }
  normalizes :name, :tagline, with: ->(value) { value&.strip }

  default_scope -> { order("name ASC") }

  def self.ransackable_attributes(auth_object = nil)
    %w[address description location name tagline]
  end

  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob("bedlam.png")) unless image.attached?

    image
  end

  def to_param
    return id.to_s if name.nil?
    "#{id}-#{name.to_url}"
  end

  # Returns the marker info for use on maps. This includes hte latitude
  # If there is no location data,
  def marker_info(open_popup = false)
    latlng_array = latlng

    if latlng_array.present?
      {
        latlng: latlng_array,
        popup: popup_description,
        open_popup: open_popup
      }
    else
      nil
    end
  end

  # Returns an array with the latitude and longitude of the venue, based on the location.
  # Returns nil if the location data is not valid.
  def latlng
    if location.present?
      latlng_array = location.split(",")

      # If the location does not contain any arrays, or more than 2, just return nil as it is invalid.
      # Does not check if the resulting values are numeric. This can be done, but the map rendering will fail in the JavaScript
      # and not in Rails, which is less critical and will not produce a Rails error blocking the web page.
      return nil unless latlng_array.length == 2

      location.split(",")
    else
      nil
    end
  end

  def popup_description
    "<b>#{name}</b><br><br>#{escape_line_breaks(address)}".html_safe
  end
end
