module Reimbursements
  ##
  # Which income budget a credit belongs on: the only one in its cost centre and financial year
  # carrying its nominal code. Several, or none, and a person decides. Reconcile's import and the
  # ledger's "Link credits" both ask here, so a row is judged the same way at import and after.
  class CreditBudgetMatcher
    def initialize(budgets:, financial_years:, cost_centres:)
      @income_budgets = budgets.select(&:income?)
      @financial_years = financial_years
      @cost_centres = cost_centres
    end

    def budget_for(row, cost_centre)
      Reconciliation.match_credit_to_budget(row, candidates(row, cost_centre))
    end

    # The income budgets +row+ may link to: in its cost centre and in the financial year its date
    # falls in. Every reader of a credit (matcher, shared-code note, pair notes) comes through here.
    def candidates(row, cost_centre)
      year_ids = FinancialYear.covering(row.date, @financial_years).map(&:id)
      in_centre = @income_budgets.select { |budget| in_cost_centre?(budget.cost_centre_id, cost_centre) }
      Reconciliation.in_credit_years(in_centre, year_ids)
    end

    # A record with no cost centre (no budget, or a nil Budget#cost_centre_id) belongs to the row's
    # centre only while exactly one centre is configured. Once a second exists, stop guessing: the
    # row stays unmatched until someone gives its budget a centre, instead of paying the wrong pot.
    def in_cost_centre?(record_cost_centre_id, cost_centre)
      return record_cost_centre_id == cost_centre.id if record_cost_centre_id

      @cost_centres.one?
    end

    # A stored row's centre, by the same rule: a row with none is the single centre's, or nobody's.
    def cost_centre_of(actual)
      @cost_centres.find { |centre| centre.id == actual.cost_centre_id } ||
        (@cost_centres.first if actual.cost_centre_id.nil? && @cost_centres.one?)
    end
  end
end
