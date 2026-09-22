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

    # reconciliation_status value stamped on both legs of an offsetting pair
    # (an accrual and its reversal, a journal booked and re-booked). Anything
    # else — including a blank status — is an ordinary ledger row.
    STATUS_OFFSET = "offset".freeze

    # reconciliation_status value stamped on a credit row finance has split
    # across several income budgets. It is what the ledger view and the CSV
    # read to say "Apportioned" rather than leaving the row looking unlinked;
    # the allocations themselves are the record of who got what.
    STATUS_APPORTIONED = "apportioned".freeze

    belongs_to :expense, class_name: "Reimbursements::Expense", optional: true,
                         inverse_of: :eusa_actuals
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    # Which pot this ledger row belongs to, resolved at import from the export's
    # own Cost Centre column (see Admin::Reimbursements::ReconcileController).
    #
    # This is the ONLY record of a row's cost centre — deliberately not stored
    # alongside the exported code as a string, since two sources of the same fact
    # can only ever disagree. The exported
    # code still exists where attribution actually needs it — on the parser's
    # Reconciliation::ActualsRow — it just isn't persisted twice.
    #
    # Optional, because a row whose code matched no configured cost centre, or
    # that arrived with the column blank, genuinely has no centre, and guessing
    # one would file real spend under the wrong pot.
    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true

    # An offsetting pair's two legs each point at the other, so this reads the
    # same from either side.
    belongs_to :offset_of, class_name: "Reimbursements::EusaActual", optional: true,
                           inverse_of: :offset_counterpart
    has_one :offset_counterpart, class_name: "Reimbursements::EusaActual",
                                 foreign_key: :offset_of_id, inverse_of: :offset_of,
                                 dependent: :nullify

    # Each income budget's share of this row, when finance has split it. Only
    # ever populated on a credit row (see #apportionable?).
    has_many :allocations, class_name: "Reimbursements::ActualAllocation",
                           foreign_key: :eusa_actual_id, inverse_of: :eusa_actual,
                           dependent: :destroy

    # EVERY write path lands here — the reconcile apply, an offsetting pair, a
    # hand fix in a console — so the ledger cannot acquire a second spelling of
    # one month again. The parser normalises too (so a paste's dedup bucket key
    # matches what is stored) and this is the backstop under it.
    # Reconciliation.normalise_period is the ONE definition; it is a pure
    # function with no Rails dependencies, so the model may call it.
    before_validation :normalise_period

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

    # Splittable across several income budgets: a credit that landed, attached
    # to nothing yet, and not an offsetting leg.
    #
    # DEBITS are deliberately out. A debit row is split by converting it into
    # several expenses, which already works (#convertible_to_expense?), and a
    # debit budget's figure totals through its EXPENSES rather than through
    # budget_id — a different mechanism that allocations would not reach.
    # An offsetting leg nets to zero against its counterpart, so apportioning
    # one would invent income, exactly as converting one would invent spend.
    def apportionable?
      credit.present? && credit.positive? && self[:budget_id].blank? &&
        self[:expense_id].blank? && !offset? && !apportioned?
    end

    def apportioned? = allocations.any?

    # A row nobody has finished with: attached to no claim and no budget, not a
    # leg of an offsetting pair, not split across income lines.
    #
    # The ONE definition, because two screens act on it and must not disagree:
    # the ledger's default "needs attention" filter — which is the list of what
    # is left to do after a reconcile — and DatabaseStore#unattributed_actuals,
    # the overview card that stops unlinked spend disappearing. They were the
    # same predicate written twice; a row the ledger hid but the card counted
    # would be money with no screen to resolve it on.
    def needs_attention?
      !offset? && self[:expense_id].blank? && self[:budget_id].blank? && !apportioned?
    end

    # Whether this row can be paired with another as an offsetting pair by
    # hand. It is #needs_attention? plus "carries a figure at all".
    #
    # Only an UNFINISHED row: stamping a row that is linked to a claim or an
    # income line as offset would hide real spend from every rollup AND leave
    # the claim reading Paid with nothing behind it. That restriction is also
    # exactly the re-pair case, since "Not offsetting" returns both legs to
    # precisely this state.
    def pairable?
      needs_attention? && signed_amount != 0
    end

    # Debits positive, credits negative — the sign an offsetting pair has to
    # cancel. Read off debit and credit rather than the stored `net` column,
    # which is parsed separately from the export's own Net cell and can be
    # blank or disagree (the reason EusaActual.net derives every rollup).
    def signed_amount
      (debit || 0) - (credit || 0)
    end

    # The rows this one could cancel out with: the HARD requirements
    # Reconciliation.detect_offsetting_pairs applies, and nothing softer.
    #
    # Same absolute amount, opposite sign, same nominal code, same financial
    # year, same cost centre — the gates the automatic detector will not pair
    # across. The detector then SCORES the survivors on reference, period,
    # narrative and date distance; this deliberately does not, because a person
    # is choosing here and the governing asymmetry runs the other way: a false
    # positive stamps real spend as noise and hides it, while an extra row on a
    # picker costs a glance.
    #
    # The cost centre is the gate with most at stake, which is why it holds
    # here as well as in the detector: two unrelated real transactions of the
    # same size on the same code in two different pots, stamped as cancelling
    # out, hide real spend from BOTH pots' rollups. It is enforced in the MODEL
    # rather than by scoping the picker's source, because #confirm_offset
    # re-checks through this same method and the "Mark as offsetting" link
    # carries no cost centre at all.
    #
    # Unlike the detector, a row with NO cost centre pairs with another that
    # has none: those predate cost centres, and the portal reads an unplaced
    # row as belonging everywhere rather than nowhere (DatabaseStore#in_year
    # states the same leniency). An unplaced row and a placed one still differ.
    def offset_candidates(rows)
      rows.select do |row|
        row.id != id && row.pairable? &&
          row.signed_amount == -signed_amount &&
          row.nominal_code.to_s == nominal_code.to_s &&
          row.financial_year_id == financial_year_id &&
          row.cost_centre_id == cost_centre_id
      end
    end

    # Whether this row answers a free-text search of the ledger: its narrative,
    # its EUSA reference, its nominal code or either amount.
    #
    # Amounts are compared with the separators a person types stripped out
    # ("£1,340" and "1340.00" are the same row), because the narrative is
    # frequently a payment-run label and the AMOUNT is the only thing the
    # operator has to go on.
    def matches_search?(term)
      term = term.to_s.strip.downcase
      return true if term.blank?

      haystacks = [ narrative, narrative_1, ref, nominal_code ].compact.map(&:downcase)
      return true if haystacks.any? { |field| field.include?(term) }

      number = term.delete("£, ")
      return false if number.blank?

      [ debit, credit ].compact.any? { |amount| amount.to_s.include?(number) }
    end

    # What a split has to add up to: credits less debits, the same derivation
    # EusaActual.net uses (negated, since this is the income side) and so the
    # exact figure Budget#credit_actual_total would have counted had the row
    # been attached whole.
    #
    # NOT the stored +net+ column. That is parsed from the export's own Net
    # cell, which is a second statement of the same fact — it can be blank on
    # a hand-created row and can disagree with the debit/credit pair every
    # rollup actually reads. Splitting against a figure no rollup reads is how
    # the parts would stop summing to the whole.
    def apportionable_total = -EusaActual.net([ self ])

    def allocated_total = allocations.sum { |allocation| allocation.amount || 0 }

    # The budgets a split was divided between, each with its share:
    # "Show A £2,500.00; Show B £1,500.00". Blank when the row is not split.
    #
    # On the MODEL rather than in a helper because the ledger page and the
    # Actuals export both print it, and a finance user reading the CSV must
    # not be told something different from one reading the screen. The "£" is
    # kept even in the export, where amounts are normally bare numerals: this
    # is a description of several amounts, not a column anything sums.
    #
    # Ordered by share, largest first, then by name — stable between renders,
    # rather than following insertion order.
    def allocation_summary
      allocations
        .sort_by { |a| [ -(a.amount || 0), a.budget&.display_name.to_s ] }
        .map { |a| "#{a.budget&.display_name.presence || '(budget gone)'} #{money(a.amount)}" }
        .join("; ")
    end

    private

    def normalise_period
      return if period.nil?

      self.period = Reconciliation.normalise_period(period)
    end

    # number_to_currency with the same unit reimbursements_money uses, so the
    # summary reads identically to every other money figure in the portal.
    def money(amount)
      ActiveSupport::NumberHelper.number_to_currency(amount || 0, unit: "£")
    end
  end
end
