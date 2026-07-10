require "test_helper"
require "bigdecimal"

module Reimbursements
  class EusaActualTest < ActiveSupport::TestCase
    test "carries actuals attributes with defaults" do
      actual = EusaActual.new(record_id: "recAct1", nominal_code: "439999", narrative: "Alice",
        debit: BigDecimal("123.45"), credit: BigDecimal("0"))
      assert_equal "recAct1", actual.record_id
      assert_equal "439999", actual.nominal_code
      assert_empty actual.linked_expense_ids
      assert_empty actual.linked_budget_ids
    end

    test "dedup_key matches a freshly-parsed row with the same nominal/narrative/amounts" do
      actual = EusaActual.new(record_id: "recAct1", nominal_code: "439999", narrative: "Alice Producer",
        debit: BigDecimal("123.45"), credit: BigDecimal("0"))
      # Same values as an ActualsRow the reconcile paste would produce.
      parsed_key = Reconciliation.actuals_row_dedup_key("439999", "Alice Producer",
        BigDecimal("123.45"), BigDecimal("0"))
      assert_equal parsed_key, actual.dedup_key
    end

    test "dedup_key differs when the amount differs" do
      a = EusaActual.new(record_id: "r1", nominal_code: "439999", narrative: "Alice",
        debit: BigDecimal("100.00"), credit: BigDecimal("0"))
      b = EusaActual.new(record_id: "r2", nominal_code: "439999", narrative: "Alice",
        debit: BigDecimal("200.00"), credit: BigDecimal("0"))
      refute_equal a.dedup_key, b.dedup_key
    end
  end
end
