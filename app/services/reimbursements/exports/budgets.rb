module Reimbursements
  module Exports
    ##
    # Budgets with every rollup the budgets table and the nominal-code overview
    # show, in the same order and with the same meanings:
    #
    # * Initial / Current forecast — what was planned, and the latest logged
    #   revision (blank when none has been logged).
    # * Projected — the current plan: the latest forecast, falling back to the
    #   initial figure.
    # * Committed — Approved + Submitted + Paid; Pipeline — Pending only, kept
    #   separate so Committed keeps its meaning.
    # * Paid (portal) vs EUSA actual — the portal's view of settled spend beside
    #   the EUSA ledger's. A divergence between the two is a reconciliation
    #   signal, which is exactly why both travel in the export.
    # * Expected outturn — the greater of the projection and what's already
    #   spent or committed, so the number never drops below reality. EMPTY for an
    #   Income budget: the same max there is best-case income, the opposite
    #   direction, so a number would mislead (see Budget#expected_outturn).
    # * Remaining (forecast - committed) and Variance (forecast - initial) are
    #   blank without a forecast, and Variance is legitimately negative when the
    #   forecast came in under the original plan.
    #
    # All amounts are excl-VAT, mirroring the BACS spreadsheet.
    class Budgets < Base
      HEADERS = [ "Budget", "Nominal code", "Type", "Visible", "Initial", "Current forecast",
                  "Projected", "Committed", "Pipeline", "Paid (portal)", "EUSA actual",
                  "Expected outturn", "Remaining", "Variance", "Owners" ].freeze
      SHEET_NAME = "Budgets".freeze
      SLUG = "budgets".freeze

      private

      def row(budget)
        [
          budget.name, budget.nominal_code, budget.budget_type,
          budget.active ? "Visible" : "Hidden",
          budget.initial_budget, budget.current_forecast, budget.projected_amount,
          budget.committed_amount, budget.pipeline_amount, budget.paid_portal_amount,
          budget.eusa_actual_amount, budget.expected_outturn,
          budget.remaining, budget.variance, owner_names(budget)
        ]
      end

      # The owners association is preloaded by the store, so this costs no
      # per-budget query however many budgets are exported.
      def owner_names(budget)
        budget.owners.filter_map { |owner| owner.name.presence }.join(", ")
      end
    end
  end
end
