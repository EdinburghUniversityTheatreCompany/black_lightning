# == Schema Information
#
# Table name: reimbursements_eusa_actuals
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  cost_centre           :string(255)      default(""), not null
#  credit                :decimal(12, 2)
#  date                  :date
#  debit                 :decimal(12, 2)
#  imported_at           :datetime
#  narrative             :text(65535)
#  narrative_1           :text(65535)
#  net                   :decimal(12, 2)
#  nominal_code          :string(255)      default(""), not null
#  period                :string(255)
#  reconciliation_status :string(255)
#  ref                   :string(255)
#  source_month          :string(255)      default(""), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  airtable_record_id    :string(255)
#  budget_id             :bigint
#  cost_centre_id        :bigint
#  expense_id            :bigint
#  financial_year_id     :bigint
#  offset_of_id          :bigint
#
# Indexes
#
#  index_reimbursements_eusa_actuals_on_airtable_record_id     (airtable_record_id) UNIQUE
#  index_reimbursements_eusa_actuals_on_budget_id              (budget_id)
#  index_reimbursements_eusa_actuals_on_cost_centre_id         (cost_centre_id)
#  index_reimbursements_eusa_actuals_on_expense_id             (expense_id)
#  index_reimbursements_eusa_actuals_on_financial_year_id      (financial_year_id)
#  index_reimbursements_eusa_actuals_on_nominal_code           (nominal_code)
#  index_reimbursements_eusa_actuals_on_offset_of_id           (offset_of_id)
#  index_reimbursements_eusa_actuals_on_period                 (period)
#  index_reimbursements_eusa_actuals_on_reconciliation_status  (reconciliation_status)
#  index_reimbursements_eusa_actuals_on_source_month           (source_month)
#
# Foreign Keys
#
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#  fk_rails_...  (expense_id => reimbursements_expenses.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#  fk_rails_...  (offset_of_id => reimbursements_eusa_actuals.id)
#
module Reimbursements
  ##
  # A row from EUSA's ledger export, imported during reconciliation.
  class EusaActual < ApplicationRecord
    include RecordId

    # reconciliation_status value stamped on both legs of an offsetting pair
    # (an accrual and its reversal, a journal booked and re-booked). Anything
    # else — including a blank status — is an ordinary ledger row.
    STATUS_OFFSET = "offset".freeze

    belongs_to :expense, class_name: "Reimbursements::Expense", optional: true,
                         inverse_of: :eusa_actuals
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    # Which pot this ledger row belongs to, taken from the export's own Cost
    # Centre column at import (see Admin::Reimbursements::ReconcileController).
    # Optional: a historical row whose code matched no configured cost centre —
    # or that arrived with the column blank — genuinely has no centre, and
    # guessing one would file real spend under the wrong pot. The +cost_centre+
    # STRING column keeps what the export said; this is the attribution.
    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true

    # An offsetting pair's two legs each point at the other, so this reads the
    # same from either side.
    belongs_to :offset_of, class_name: "Reimbursements::EusaActual", optional: true,
                           inverse_of: :offset_counterpart
    has_one :offset_counterpart, class_name: "Reimbursements::EusaActual",
                                 foreign_key: :offset_of_id, inverse_of: :offset_of,
                                 dependent: :nullify

    # The net position of a set of ledger rows, from the spending side: debits
    # less credits, so a supplier refund or a credit note reduces the figure
    # instead of inflating it. Offsetting legs are dropped rather than netted:
    # an accrual and its reversal cancel out, so neither is spend, and dropping
    # both is right even when only one leg happens to be linked to an expense.
    #
    # The single definition of "what did this cost", shared by the budget
    # rollups and the overview's unattributed list.
    def self.net(actuals)
      actuals.reject(&:offset?).sum { |a| (a.debit || 0) - (a.credit || 0) }
    end

    # The PORO exposed arrays of linked record ids; reconcile only ever links
    # one of each, so these wrap the single FKs to keep the array interface.
    def linked_expense_ids = [ self[:expense_id]&.to_s ].compact
    def linked_budget_ids = [ self[:budget_id]&.to_s ].compact

    # Key matching Reconciliation.actuals_row_dedup_key so an imported row can
    # be compared against a freshly-parsed ActualsRow to skip re-importing.
    def dedup_key
      Reconciliation.actuals_row_dedup_key(nominal_code, narrative, debit, credit)
    end

    def offset?
      reconciliation_status == STATUS_OFFSET
    end

    # Only an unlinked debit row can become a From-EUSA expense: a credit is
    # income, an already-linked row would double-count, and an offsetting leg is
    # bookkeeping noise that nets to zero against its counterpart — turning one
    # into an expense would invent spend that never happened.
    def convertible_to_expense?
      debit.present? && debit.positive? && self[:expense_id].blank? && !offset?
    end
  end
end
