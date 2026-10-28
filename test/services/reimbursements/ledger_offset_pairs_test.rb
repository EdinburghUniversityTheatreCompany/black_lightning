require "test_helper"

module Reimbursements
  class LedgerOffsetPairsTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @estimate = leg(debit: BigDecimal("500"), period: "05", ref: "JNL0442", date: Date.new(2026, 9, 7))
    end

    def leg(**attrs)
      create_reimbursements_eusa_actual(nominal_code: "331130", narrative: "P5 accrued ticket income",
                                        cost_centre_id: CostCentre.order(:id).first.id, **attrs)
    end

    def pairs = LedgerOffsetPairs.new(EusaActual.all.to_a)

    # One estimate, two income rows of its amount: either may be its reversal. Both are listed and
    # both held back, so a weak-evidence reversal is never linked as income.
    test "every possible partner is listed, and only the best strong pair starts ticked" do
      reversal = leg(credit: BigDecimal("500"), period: "06", ref: "JNL0442", date: Date.new(2026, 10, 4))
      takings = leg(credit: BigDecimal("500"), period: "09", ref: "SI0099", narrative: "Box office",
                    date: Date.new(2027, 1, 20))

      listed = pairs.pairs.map { |pair| [ pair.credit, pair.ticked ] }

      assert_equal [ [ reversal, true ], [ takings, false ] ], listed
      assert_equal [ @estimate.id, reversal.id, takings.id ].to_set, pairs.paired_ids
    end

    test "a strong pair whose row a stronger pair took starts unticked" do
      first = leg(credit: BigDecimal("500"), period: "05", ref: "JNL0442", date: Date.new(2026, 9, 7))
      second = leg(credit: BigDecimal("500"), period: "06", ref: "JNL0442", date: Date.new(2026, 10, 4))

      assert_equal [ [ first, true ], [ second, false ] ], pairs.pairs.map { |pair| [ pair.credit, pair.ticked ] }
    end

    test "undated and placed rows have no partners" do
      leg(credit: BigDecimal("500"), date: nil)
      leg(credit: BigDecimal("500"), budget: create_reimbursements_budget(name: "Tickets", budget_type: "Income",
                                                                           nominal_code: "331130"))

      assert_empty pairs.pairs
    end
  end
end
