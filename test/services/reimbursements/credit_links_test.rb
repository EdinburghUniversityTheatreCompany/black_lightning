require "test_helper"

module Reimbursements
  class CreditLinksTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @membership = create_reimbursements_budget(name: "Membership", budget_type: "Income",
                                                 nominal_code: "359000")
      @fee = create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("640"))
    end

    def plan
      ledger = EusaActual.all.to_a
      matcher = CreditBudgetMatcher.new(budgets: Budget.all.to_a, financial_years: [],
                                        cost_centres: CostCentre.order(:id).to_a)
      CreditLinks.new(actuals: ledger, ledger: ledger, matcher: matcher)
    end

    test "an unplaced credit one income budget claims is planned onto it" do
      second = create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("215.50"))

      assert_equal [ [ @fee, @membership ], [ second, @membership ] ],
                   plan.links.map { |link| [ link.actual, link.budget ] }
      assert_equal({ @membership => [ @fee, second ] }, plan.by_budget)
    end

    test "a credit with an unplaced row of the opposite amount is held back" do
      create_reimbursements_eusa_actual(nominal_code: "359000", debit: BigDecimal("640"))

      assert_empty plan.links
      assert_equal [ @fee ], plan.held_back
    end

    test "placed, undated and debit rows are not planned" do
      create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("10"), budget: @membership)
      create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("20"), date: nil)
      create_reimbursements_eusa_actual(nominal_code: "359000", debit: BigDecimal("30"))

      assert_equal [ @fee ], plan.links.map(&:actual)
    end
  end
end
