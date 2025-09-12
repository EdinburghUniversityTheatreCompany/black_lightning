# == Schema Information
#
# Table name: carousel_items
#
# *id*::            <tt>bigint, not null, primary key</tt>
# *title*::         <tt>string(255)</tt>
# *tagline*::       <tt>text(65535)</tt>
# *is_active*::     <tt>boolean</tt>
# *carousel_name*:: <tt>string(255)</tt>
# *ordering*::      <tt>integer</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
# *url*::           <tt>string(255)</tt>
#--
# == Schema Information End
#++
class CarouselItem < ApplicationRecord
  CAROUSEL_NAMES = [ "Home" ].freeze

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
