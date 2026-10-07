# A grouping for opportunity roles (e.g. "Stage Management"). A role whose position contains one of
# the comma or newline separated +match_terms+ is suggested that department (see .suggestions).
# == Schema Information
#
# Table name: departments
# Database name: primary
#
#  id          :bigint           not null, primary key
#  match_terms :text(65535)
#  name        :string(255)      not null
#  ordering    :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_departments_on_name  (name) UNIQUE
#
class Department < ApplicationRecord
  validates :name, length: { maximum: 255 }
  validates :match_terms, length: { maximum: 65535 }
  has_many :opportunity_roles, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  normalizes :name, with: ->(name) { name&.strip }

  default_scope { order(:ordering) }

  def match_term_list
    match_terms.to_s.split(/[,\n]/).map { |term| term.strip.downcase }.reject(&:blank?)
  end

  # Matches the name case-insensitively.
  def self.find_or_build_by_name(name)
    name = name.to_s.strip
    return if name.blank?

    find_by("LOWER(name) = LOWER(?)", name) || new(name: name)
  end

  # For the department-suggest Stimulus controller.
  def self.suggestions
    all.map { |department| { name: department.name, terms: department.match_term_list } }
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunity_roles]
  end
end
