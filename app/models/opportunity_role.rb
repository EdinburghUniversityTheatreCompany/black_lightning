# == Schema Information
#
# Table name: opportunity_roles
#
# *id*::             <tt>bigint, not null, primary key</tt>
# *opportunity_id*:: <tt>integer, not null</tt>
# *position*::       <tt>string(255)</tt>
# *category*::       <tt>integer, default(0), not null</tt>
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
# The +category+ enum drives the public listing's tabs and filters.
##
class OpportunityRole < ApplicationRecord
  belongs_to :opportunity, touch: true

  enum :category, {
    acting: 0,
    directing: 1,
    stage: 2,
    lighting: 3,
    sound: 4,
    set: 5,
    costume: 6,
    writing: 7,
    production: 8,
    marketing: 9,
    foh: 10,
    other: 11
  }, default: :other

  validates :position, presence: true
  validates :category, presence: true

  normalizes :position, with: ->(position) { position&.strip }

  default_scope { order(:ordering) }

  # Most categories humanise nicely; a few need a custom display label.
  CATEGORY_LABELS = { "foh" => "FOH" }.freeze

  def category_label
    CATEGORY_LABELS[category] || category.humanize
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[category position note ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[opportunity]
  end
end
