require "test_helper"

module Reimbursements
  module Exports
    ##
    # The Actuals export's Budget cell for a row split across several income
    # budgets. A finance user reading the CSV and a finance user reading the
    # ledger page must not be told two different things about where the money
    # went, so both read one derivation.
    class ActualsTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      def csv_rows(store)
        CSV.parse(Actuals.new(store: store).to_csv(store.eusa_actuals), headers: true)
      end

      def budget_cell(store)
        csv_rows(store).first["Budget"]
      end

      setup do
        @payout = create_reimbursements_eusa_actual(credit: BigDecimal("4000"),
                                                    narrative: "STRIPE PAYOUT AUG")
        @show_a = create_reimbursements_budget(name: "Show A", budget_type: "Income")
        @show_b = create_reimbursements_budget(name: "Show B", budget_type: "Income")
      end

      test "a split row's Budget cell names every budget and its share" do
        DatabaseStore.new.apportion_actual!(@payout.id, [
          { budget_id: @show_a.id, amount: BigDecimal("2500") },
          { budget_id: @show_b.id, amount: BigDecimal("1500") }
        ])

        assert_equal "Show A £2,500.00; Show B £1,500.00", budget_cell(DatabaseStore.new)
      end

      test "a split row's Status names the split" do
        DatabaseStore.new.apportion_actual!(
          @payout.id, [ { budget_id: @show_a.id, amount: BigDecimal("4000") } ]
        )

        assert_equal "Apportioned", csv_rows(DatabaseStore.new).first["Status"]
      end

      test "a row attached to one budget whole still names just that budget" do
        @payout.update!(budget: @show_a)

        assert_equal "Show A", budget_cell(DatabaseStore.new)
      end

      # Shares can sit in different areas, so one Area cell would be a lie
      # rather than a blank — the reason Batches carries no Area column.
      test "a split row's Area cell is blank rather than naming one of several" do
        area = create_reimbursements_area(name: "Cogito")
        @show_a.update!(area: area)
        DatabaseStore.new.apportion_actual!(@payout.id, [
          { budget_id: @show_a.id, amount: BigDecimal("2500") },
          { budget_id: @show_b.id, amount: BigDecimal("1500") }
        ])

        assert_nil csv_rows(DatabaseStore.new).first["Area"]
      end

      # Every cell goes through CellSanitizer, or a budget somebody named
      # "=cmd|..." reaches Excel as a formula.
      test "the Budget cell is sanitized" do
        evil = create_reimbursements_budget(name: "=1+1", budget_type: "Income")
        DatabaseStore.new.apportion_actual!(
          @payout.id, [ { budget_id: evil.id, amount: BigDecimal("4000") } ]
        )

        assert_equal CellSanitizer.cell("=1+1 £4,000.00"), budget_cell(DatabaseStore.new)
        assert_not budget_cell(DatabaseStore.new).start_with?("=")
      end
    end
  end
end
