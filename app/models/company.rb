
##
# A theatre company or society that posts opportunities.
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
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 255 }
  validates :slug, :website, :instagram, length: { maximum: 255 }
  has_many :opportunities, dependent: :nullify
  has_many :events, dependent: :nullify

  acts_as_url :name, url_attribute: :slug

  normalizes :name, with: ->(name) { name&.strip }
  normalizes :instagram, with: ->(value) { value&.strip&.delete_prefix("@").presence }

  scope :internal_first, -> { order(internal: :desc, name: :asc) }
  scope :unreviewed, -> { where(reviewed: false) }

  # The new record is saved by belongs_to autosave when the parent opportunity is saved.
  def self.find_or_build_by_name(name)
    name = name.to_s.strip
    return if name.blank?

    find_by("LOWER(name) = LOWER(?)", name) || new(name: name)
  end

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
