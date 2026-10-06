# == Schema Information
#
# Table name: reimbursements_actual_allocations
# Database name: primary
#
#  id             :bigint           not null, primary key
#  amount         :decimal(12, 2)   not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  budget_id      :bigint           not null
#  eusa_actual_id :bigint           not null
#
# Indexes
#
#  index_reimb_actual_allocations_on_actual_and_budget        (eusa_actual_id,budget_id) UNIQUE
#  index_reimbursements_actual_allocations_on_budget_id       (budget_id)
#  index_reimbursements_actual_allocations_on_eusa_actual_id  (eusa_actual_id)
#
# Foreign Keys
#
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (eusa_actual_id => reimbursements_eusa_actuals.id)
#
module Reimbursements
  ##
  # One budget's share of a single EUSA credit row. +amount+ is positive and unsigned (the row's
  # direction says income or spend). The shares must sum to the row's income, which no per-row
  # validation can see: DatabaseStore#apportion_actual! owns that.
  class ActualAllocation < ApplicationRecord
    self.table_name = "reimbursements_actual_allocations"

    belongs_to :eusa_actual, class_name: "Reimbursements::EusaActual",
                             inverse_of: :allocations
    belongs_to :budget, class_name: "Reimbursements::Budget"

    validates :amount, numericality: { greater_than: 0 }
    validates :budget_id, uniqueness: { scope: :eusa_actual_id }
    validate :actual_is_not_attached_whole

    private

    # Budget#credit_actual_total adds these shares to the rows attached whole, so the two sets must
    # be disjoint or a row counts twice. apportion_actual! clears budget_id, but MySQL cannot check
    # that across two tables.
    def actual_is_not_attached_whole
      return if eusa_actual.nil? || eusa_actual[:budget_id].blank?

      errors.add(:eusa_actual, "is already attached to a budget in full")
    end
  end
end
