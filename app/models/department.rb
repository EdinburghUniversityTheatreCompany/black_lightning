
##
# A grouping for opportunity roles (e.g. "Stage Management", "Lighting").
#
# +match_terms+ is a comma/newline-separated list of substrings; a role position that contains any
# of a department's terms is suggested that department (see Department.match_for and the
# department-suggest Stimulus controller).
##
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
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :match_terms, length: { maximum: 65535 }
  has_many :opportunity_roles, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  normalizes :name, with: ->(name) { name&.strip }

  default_scope { order(:ordering) }

  # The match terms as a clean lower-cased list.
  def match_term_list
    match_terms.to_s.split(/[,\n]/).map { |term| term.strip.downcase }.reject(&:blank?)
  end

  # The first department (by ordering) whose any match term appears in the position, or nil.
  def self.match_for(position)
    text = position.to_s.downcase
    return if text.blank?

    all.find { |department| department.match_term_list.any? { |term| text.include?(term) } }
  end

  # Find an existing department by name (case-insensitive) or build a new one.
  def self.find_or_build_by_name(name)
    name = name.to_s.strip
    return if name.blank?

    find_by("LOWER(name) = LOWER(?)", name) || new(name: name)
  end

  # Departments + their match terms, for the department-suggest Stimulus controller.
  def self.suggestions
    all.map { |department| { name: department.name, terms: department.match_term_list } }
  end

  def to_label
    name
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunity_roles]
  end
end
