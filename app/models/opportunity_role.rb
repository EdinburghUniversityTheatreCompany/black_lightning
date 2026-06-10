# == Schema Information
#
# Table name: opportunity_roles
#
# *id*::             <tt>bigint, not null, primary key</tt>
# *opportunity_id*:: <tt>integer, not null</tt>
# *department_id*::  <tt>bigint</tt>
# *position*::       <tt>string(255)</tt>
# *note*::           <tt>string(255)</tt>
# *ordering*::       <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

##
# A single role/position within an Opportunity (e.g. "Stage Manager").
#
# Each role belongs to a Department (the grouping used by the public listing's filter). The
# department is usually auto-suggested from the position text; +department_name+ is a virtual
# field so the form can submit (and, on the admin form, create) a department by name.
##
class OpportunityRole < ApplicationRecord
  belongs_to :opportunity, touch: true
  belongs_to :department, optional: true

  # +department_name+ resolves to a Department (created if needed) in a before_validation hook.
  # Only the admin role form offers tagging, so in practice public submitters pick an existing
  # department rather than creating one.
  attr_writer :department_name

  before_validation :assign_department_from_name

  validates :position, presence: true

  normalizes :position, with: ->(position) { position&.strip }

  default_scope { order(:ordering) }

  # The typed department name, falling back to the associated department so the form pre-fills.
  def department_name
    return @department_name if defined?(@department_name)

    department&.name
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[position note ordering department_id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunity department]
  end

  private

  def assign_department_from_name
    return unless defined?(@department_name)

    name = @department_name.to_s.strip
    self.department = name.present? ? Department.find_or_build_by_name(name) : nil
  end
end
