# == Schema Information
#
# Table name: reimbursements_financial_years
# Database name: primary
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(FALSE), not null
#  ends_on    :date
#  label      :string(255)      not null
#  starts_on  :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_reimbursements_financial_years_on_active  (active)
#  index_reimbursements_financial_years_on_label   (label) UNIQUE
#
module Reimbursements
  ##
  # A financial year ("Fringe 2026") — orthogonal to cost centre: each year has
  # its own budgets, expenses and actuals. One year is active at a time; past
  # years stay viewable (the year-selector UI is post-cutover work, but the
  # schema and invariant live here from the start).
  class FinancialYear < ApplicationRecord
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :restrict_with_error
    has_many :expenses, class_name: "Reimbursements::Expense", dependent: :restrict_with_error
    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual", dependent: :restrict_with_error

    validates :label, presence: true, uniqueness: true
    validate :only_one_active

    scope :active, -> { where(active: true) }

    def self.current
      active.first
    end

    def record_id = id&.to_s

    private

    def only_one_active
      return unless active?
      return unless self.class.active.where.not(id: id).exists?

      errors.add(:active, "is already set on another financial year.")
    end
  end
end
