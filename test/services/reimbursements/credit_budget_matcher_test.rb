require "test_helper"

module Reimbursements
  class CreditBudgetMatcherTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @this_year, @next_year = create_reimbursements_tax_years
      @fringe = CostCentre.order(:id).first
      @row = create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("640"),
                                               date: Date.new(2026, 9, 20))
    end

    def matcher(cost_centres: CostCentre.order(:id).to_a)
      CreditBudgetMatcher.new(budgets: Budget.all.to_a, financial_years: [ @this_year, @next_year ],
                              cost_centres: cost_centres)
    end

    test "the one income budget with the code, in the row's year and centre, is the match" do
      membership = create_reimbursements_budget(name: "Membership", budget_type: "Income",
                                                nominal_code: "359000", financial_year: @this_year)
      create_reimbursements_budget(name: "Membership", budget_type: "Income", nominal_code: "359000",
                                   financial_year: @next_year)
      create_reimbursements_budget(name: "Set", nominal_code: "359000")

      assert_equal membership, matcher.budget_for(@row, @fringe)
    end

    test "two income budgets with the code leave the row unmatched" do
      2.times { |n| create_reimbursements_budget(name: "Hire #{n}", budget_type: "Income", nominal_code: "359000") }

      assert_nil matcher.budget_for(@row, @fringe)
    end

    test "a budget with no centre counts only while one centre is configured" do
      create_reimbursements_budget(name: "Membership", budget_type: "Income", nominal_code: "359000")
      termtime = create_second_reimbursements_cost_centre

      assert_not_nil matcher(cost_centres: [ @fringe ]).budget_for(@row, @fringe)
      assert_nil matcher(cost_centres: [ @fringe, termtime ]).budget_for(@row, @fringe)
    end

    test "a stored row's centre: its own, else the single configured one, else none" do
      termtime = create_second_reimbursements_cost_centre

      assert_equal @fringe, matcher(cost_centres: [ @fringe ]).cost_centre_of(@row)
      assert_nil matcher(cost_centres: [ @fringe, termtime ]).cost_centre_of(@row)

      @row.update!(cost_centre_id: termtime.id)

      assert_equal termtime, matcher(cost_centres: [ @fringe, termtime ]).cost_centre_of(@row)
    end
  end
end
