# == Schema Information
#
# Table name: reimbursements_claim_shares
# Database name: primary
#
#  id             :bigint           not null, primary key
#  amount         :decimal(12, 2)   not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  eusa_actual_id :bigint           not null
#  expense_id     :bigint           not null
#
# Indexes
#
#  index_reimbursements_claim_shares_on_eusa_actual_id  (eusa_actual_id)
#  index_reimbursements_claim_shares_on_expense_id      (expense_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (eusa_actual_id => reimbursements_eusa_actuals.id)
#  fk_rails_...  (expense_id => reimbursements_expenses.id)
#
module Reimbursements
  ##
  # One claim's part of a single EUSA debit that paid several claims together. +amount+ is
  # positive. The shares must sum to the row's debit and each claim takes at most one, which no
  # per-row validation can see: DatabaseStore#share_actual! owns that.
  class ClaimShare < ApplicationRecord
    belongs_to :eusa_actual, class_name: "Reimbursements::EusaActual", inverse_of: :claim_shares
    belongs_to :expense, class_name: "Reimbursements::Expense", inverse_of: :claim_share

    validates :amount, numericality: { greater_than: 0 }
    # One share per claim, or its spend would count twice; the unique index is the backstop.
    validates :expense_id, uniqueness: true
  end
end
