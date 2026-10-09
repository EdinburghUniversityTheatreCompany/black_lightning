
##
# A position within an Opportunity (e.g. "Stage Manager"), grouped by Department for the public
# listing's filter.
##
# == Schema Information
#
# Table name: opportunity_roles
# Database name: primary
#
#  id             :bigint           not null, primary key
#  note           :string(255)
#  ordering       :integer
#  position       :string(255)      not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  department_id  :bigint
#  opportunity_id :integer          not null
#
# Indexes
#
#  index_opportunity_roles_on_department_id   (department_id)
#  index_opportunity_roles_on_opportunity_id  (opportunity_id)
#
# Foreign Keys
#
#  fk_rails_...  (department_id => departments.id)
#  fk_rails_...  (opportunity_id => opportunities.id)
#
class OpportunityRole < ApplicationRecord
  validates :position, presence: true, length: { maximum: 255 }
  validates :note, length: { maximum: 255 }
  belongs_to :opportunity, touch: true
  belongs_to :department, optional: true

  before_validation :assign_department_from_name

  normalizes :position, with: ->(position) { position&.strip }

  default_scope { order(:ordering) }

  # Virtual field so either form can submit, and create, a department by name: resolved to a
  # Department (built if new, saved by belongs_to autosave) before validation. A row whose only
  # edit is its department must count as changed, or the opportunity's nested save skips it and
  # the pick is lost.
  def department_name=(name)
    @department_name = name
    department_id_will_change! unless name.to_s.strip.casecmp?(department&.name.to_s)
  end

  # Falls back to the department so the form pre-fills.
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
    self.department = Department.find_or_build_by_name(@department_name) if defined?(@department_name)
  end
end
