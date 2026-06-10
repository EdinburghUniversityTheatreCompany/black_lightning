# == Schema Information
#
# Table name: departments
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *match_terms*:: <tt>text(65535)</tt>
# *ordering*::    <tt>integer</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

##
# A grouping for opportunity roles (e.g. "Stage Management", "Lighting").
#
# +match_terms+ is a comma/newline-separated list of substrings; a role position that contains any
# of a department's terms is suggested that department (see Department.match_for and the
# department-suggest Stimulus controller).
##
class Department < ApplicationRecord
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
