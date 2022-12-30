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

  default_scope -> { order('name ASC') }

  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob('bedlam.png')) unless image.attached? 

    return image
  end

  def to_param
    return "#{id}-#{name.to_url}"
  end

  def marker_info
    if location.present?
      return {
        latlng: latlng,
        popup: popup_description
      }
    else
      return nil
    end
  end

  def latlng
    if location.present?
      return location.split(',')
    else
      return nil
    end
  end

  def popup_description
    return "<b>#{name}</b><br><br>#{escape_line_breaks(address)}".html_safe
  end
end
