# == Schema Information
#
# Table name: reimbursements_eusa_actuals
# Database name: primary
#
#  id                    :bigint           not null, primary key
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

    # Airtable's month label, which nothing reads or writes. The next deploy drops it.
    self.ignored_columns += %w[source_month]

    # Stamped on both legs of an offsetting pair (an accrual and its reversal).
    STATUS_OFFSET = "offset".freeze

    # Stamped on a credit row split across income budgets; the export prints it.
    # #apportioned? reads the allocations, not this.
    STATUS_APPORTIONED = "apportioned".freeze

    belongs_to :expense, class_name: "Reimbursements::Expense", optional: true,
                         inverse_of: :eusa_actuals
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    # The only record of a row's cost centre, resolved at import from the export's Cost Centre
    # column; the exported code is not stored as well. Optional: a row whose code matched no
    # centre, or arrived blank, has none, and guessing would file spend under the wrong pot.
    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true

    # The two legs of an offsetting pair point at each other.
    belongs_to :offset_of, class_name: "Reimbursements::EusaActual", optional: true,
                           inverse_of: :offset_counterpart
    has_one :offset_counterpart, class_name: "Reimbursements::EusaActual",
                                 foreign_key: :offset_of_id, inverse_of: :offset_of,
                                 dependent: :nullify

    # Each income budget's share of this row; only ever on a credit (see #apportionable?).
    has_many :allocations, class_name: "Reimbursements::ActualAllocation",
                           foreign_key: :eusa_actual_id, inverse_of: :eusa_actual,
                           dependent: :destroy

    # Every write path normalises, so the ledger cannot gain a second spelling of a month. The
    # parser does too, so a paste's dedup key matches what is stored. Reconciliation.normalise_period
    # is the one definition.
    before_validation :normalise_period

    # What the rows cost: debits less credits, so a refund reduces the figure. Offsetting legs are
    # dropped, not netted: both are noise even when only one leg is linked to an expense. The one
    # definition, shared by the budget rollups and the overview's unattributed list.
    def self.net(actuals)
      actuals.reject(&:offset?).sum { |a| (a.debit || 0) - (a.credit || 0) }
    end

    # Comparable with a freshly parsed ActualsRow, to skip re-importing.
    def dedup_key
      Reconciliation.actuals_row_dedup_key(nominal_code, narrative, debit, credit)
    end

    def offset?
      reconciliation_status == STATUS_OFFSET
    end

    # An unlinked debit. An offsetting leg nets to zero, so converting it would invent spend.
    def convertible_to_expense?
      debit.present? && debit.positive? && expense_id.blank? && !offset?
    end

    # An unattached credit that is not an offsetting leg (splitting one would invent income).
    # Debits are out on purpose: they are split by converting to several expenses, and a debit
    # budget's figure totals through its expenses, which allocations would not reach.
    def apportionable?
      credit.present? && credit.positive? && budget_id.blank? &&
        expense_id.blank? && !offset? && !apportioned?
    end

    def apportioned? = allocations.any?

    # Attached to no claim or budget, not an offsetting leg, not split. The ONE definition: the
    # ledger's default filter and DatabaseStore#unattributed_actuals both read it, or a row the
    # ledger hid but the overview counted would be money with no screen to resolve it on.
    def needs_attention?
      !offset? && expense_id.blank? && budget_id.blank? && !apportioned?
    end

    # #needs_attention? plus a figure. Only unfinished rows: offsetting a row linked to a claim
    # would hide real spend and leave the claim Paid with nothing behind it. This is also exactly
    # the state "Not offsetting" returns both legs to.
    def pairable?
      needs_attention? && signed_amount != 0
    end

    # Debits positive, credits negative. Read off debit and credit, not the stored `net`, which is
    # parsed from the export's own Net cell and can be blank or disagree.
    def signed_amount
      (debit || 0) - (credit || 0)
    end

    # The rows this one could cancel out with: the hard requirements of
    # Reconciliation.detect_offsetting_pairs, with no scoring (a person is choosing, so an extra
    # row costs a glance where a false positive hides real spend). The cost centre is checked here,
    # not by scoping the picker, because #confirm_offset re-checks through this method and the
    # "Mark as offsetting" link carries no centre. Two rows with no centre pair, as rows predating
    # cost centres count as belonging everywhere.
    def offset_candidates(rows)
      rows.select do |row|
        row.id != id && row.pairable? &&
          row.signed_amount == -signed_amount &&
          row.nominal_code.to_s == nominal_code.to_s &&
          row.financial_year_id == financial_year_id &&
          row.cost_centre_id == cost_centre_id
      end
    end

    # Free-text search over narrative, reference, nominal code and either amount. Amounts are
    # compared with typed separators stripped ("£1,340" finds 1340.00): the narrative is often a
    # payment-run label, so the amount is the only clue.
    def matches_search?(term)
      term = term.to_s.strip.downcase
      return true if term.blank?

      haystacks = [ narrative, narrative_1, ref, nominal_code ].compact.map(&:downcase)
      return true if haystacks.any? { |field| field.include?(term) }

      number = term.delete("£, ")
      return false if number.blank?

      [ debit, credit ].compact.any? { |amount| amount.to_s.include?(number) }
    end

    # What a split must add up to: credits less debits, the figure Budget#credit_actual_total would
    # have counted had the row been attached whole. NOT the stored `net`, which can be blank or
    # disagree with the debit/credit pair every rollup reads.
    def apportionable_total = -EusaActual.net([ self ])

    # "Show A £2,500.00; Show B £1,500.00", largest share first then by name; blank when not split.
    # On the model so the ledger and the CSV print the same string. The "£" stays in the export:
    # this describes several amounts and is not a column anything sums.
    def allocation_summary
      allocations.sort_by { |a| [ -a.amount, a.budget.display_name ] }
                 .map { |a| "#{a.budget.display_name} #{ActiveSupport::NumberHelper.number_to_currency(a.amount, unit: '£')}" }
                 .join("; ")
    end

    private

    def normalise_period
      return if period.nil?

      self.period = Reconciliation.normalise_period(period)
    end
  end
end
