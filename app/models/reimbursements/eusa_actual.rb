# == Schema Information
#
# Table name: reimbursements_eusa_actuals
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  cost_centre        :string(255)      default(""), not null
#  credit             :decimal(12, 2)
#  date               :date
#  debit              :decimal(12, 2)
#  imported_at        :datetime
#  narrative          :text(65535)
#  narrative_1        :text(65535)
#  net                :decimal(12, 2)
#  nominal_code       :string(255)      default(""), not null
#  period             :string(255)
#  ref                :string(255)
#  source_month       :string(255)      default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  airtable_record_id :string(255)
#  budget_id          :bigint
#  expense_id         :bigint
#  financial_year_id  :bigint
#
# Indexes
#
#  index_reimbursements_eusa_actuals_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_eusa_actuals_on_budget_id           (budget_id)
#  index_reimbursements_eusa_actuals_on_expense_id          (expense_id)
#  index_reimbursements_eusa_actuals_on_financial_year_id   (financial_year_id)
#  index_reimbursements_eusa_actuals_on_nominal_code        (nominal_code)
#  index_reimbursements_eusa_actuals_on_period              (period)
#  index_reimbursements_eusa_actuals_on_source_month        (source_month)
#
# Foreign Keys
#
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (expense_id => reimbursements_expenses.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#
module Reimbursements
  ##
  # A row from EUSA's ledger export, imported during reconciliation.
  # ActiveRecord replacement for the Airtable-era PORO (now
  # Reimbursements::Airtable::EusaActual).
  class EusaActual < ApplicationRecord
    belongs_to :expense, class_name: "Reimbursements::Expense", optional: true,
                         inverse_of: :eusa_actuals
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    def record_id = id&.to_s

    # The PORO exposed arrays of linked record ids; reconcile only ever links
    # one of each, so these wrap the single FKs to keep the array interface.
    def linked_expense_ids = [ self[:expense_id]&.to_s ].compact
    def linked_budget_ids = [ self[:budget_id]&.to_s ].compact

    # Key matching Reconciliation.actuals_row_dedup_key so an imported row can
    # be compared against a freshly-parsed ActualsRow to skip re-importing.
    def dedup_key
      Reconciliation.actuals_row_dedup_key(nominal_code, narrative, debit, credit)
    end
  end
end
