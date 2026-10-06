module Reimbursements
  module Exports
    ##
    # Budgets with every rollup the budgets table and the nominal-code overview
    # show, in the same order and with the same meanings.
    #
    # * Committed, Pipeline and Paid (portal) are ex-VAT, as the budget screens show them.
    # * Expected outturn is EMPTY for an Income budget: the "never below
    #   reality" max reads as best-case income there (Budget#expected_outturn).
    # * Remaining and Variance read the PLAN, not the forecast alone, so a line
    #   carrying only an initial figure still reports both (Budget#remaining).
    # * Area reads budget.area, not store.areas: both callers preload
    #   area: :owners.
    class Budgets < Base
      HEADERS = [ "Budget", "Nominal code", "Type", "Visible", "Initial", "Current forecast",
                  "Projected", "Committed", "Pipeline", "Paid (portal)", "EUSA actual",
                  "Expected outturn", "Remaining", "Variance", "Owners",
                  "Cost centre", "Area" ].freeze
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
          budget.remaining, budget.variance, owner_names(budget),
          cost_centre_name(budget.cost_centre_id), budget.area&.name
        ]
      end

      def owner_names(budget)
        budget.owners.filter_map { |owner| owner.name.presence }.join(", ")
      end
    end
  end
end
