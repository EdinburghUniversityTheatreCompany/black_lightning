
##
# A theatre company or society that posts opportunities.
#
# +internal+ marks EUTC/affiliated companies, which are surfaced first in listings.
# The +slug+ (generated from the name) gives stable, shareable per-company filter URLs.
##
# == Schema Information
#
# Table name: companies
# Database name: primary
#
#  id         :bigint           not null, primary key
#  instagram  :string(255)
#  internal   :boolean          default(FALSE), not null
#  name       :string(255)      not null
#  reviewed   :boolean          default(FALSE), not null
#  slug       :string(255)
#  website    :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_companies_on_slug  (slug) UNIQUE
#
class Company < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :slug, length: { maximum: 255 }
  validates :website, length: { maximum: 255 }
  validates :instagram, length: { maximum: 255 }
  has_many :opportunities, dependent: :nullify
  has_many :events, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  acts_as_url :name, url_attribute: :slug

  normalizes :name, with: ->(name) { name&.strip }
  normalizes :instagram, with: ->(value) { value&.strip&.delete_prefix("@").presence }

  scope :internal_first, -> { order(internal: :desc, name: :asc) }
  scope :unreviewed, -> { where(reviewed: false) }

  # Find an existing company by name (case-insensitive) or build a new, unreviewed one.
  # The new record is persisted via belongs_to autosave when the parent opportunity is saved.
  def self.find_or_build_by_name(name)
    name = name.to_s.strip
    return if name.blank?

    find_by("LOWER(name) = LOWER(?)", name) || new(name: name)
  end

  # Full Instagram URL for the stored handle (accepts a bare handle or a full URL).
  def instagram_url
    return if instagram.blank?
    return instagram if instagram.start_with?("http")

    "https://instagram.com/#{instagram}"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name slug internal website instagram reviewed]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunities events]
  end
end
