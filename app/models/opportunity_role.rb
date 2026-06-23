
##
# A single role/position within an Opportunity (e.g. "Stage Manager").
#
# Each role belongs to a Department (the grouping used by the public listing's filter). The
# department is usually auto-suggested from the position text; +department_name+ is a virtual
# field so the form can submit (and, on the admin form, create) a department by name.
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
