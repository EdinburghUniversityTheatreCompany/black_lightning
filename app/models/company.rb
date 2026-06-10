# == Schema Information
#
# Table name: companies
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *slug*::       <tt>string(255)</tt>
# *internal*::   <tt>boolean, default(FALSE), not null</tt>
# *website*::    <tt>string(255)</tt>
# *instagram*::  <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

##
# A theatre company or society that posts opportunities.
#
# +internal+ marks EUTC/affiliated companies, which are surfaced first in listings.
# The +slug+ (generated from the name) gives stable, shareable per-company filter URLs.
##
class Company < ApplicationRecord
  has_many :opportunities, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  acts_as_url :name, url_attribute: :slug

  normalizes :name, with: ->(name) { name&.strip }
  normalizes :instagram, with: ->(value) { value&.strip&.delete_prefix("@").presence }

  scope :internal_first, -> { order(internal: :desc, name: :asc) }

  # Full Instagram URL for the stored handle (accepts a bare handle or a full URL).
  def instagram_url
    return if instagram.blank?
    return instagram if instagram.start_with?("http")

    "https://instagram.com/#{instagram}"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name slug internal website instagram]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunities]
  end
end
