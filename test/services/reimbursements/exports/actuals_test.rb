require "test_helper"

module Reimbursements
  module Exports
    ##
    # The Actuals export for a row split across several income budgets: it
    # reads the same derivation as the ledger page, so the two cannot disagree.
    class ActualsTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      def csv_rows(store)
        CSV.parse(Actuals.new(store: store).to_csv(store.eusa_actuals), headers: true)
      end

      setup do
        @payout = create_reimbursements_eusa_actual(credit: BigDecimal("4000"),
                                                    narrative: "STRIPE PAYOUT AUG")
        @show_a = create_reimbursements_budget(name: "Show A", budget_type: "Income")
        @show_b = create_reimbursements_budget(name: "Show B", budget_type: "Income")
      end

      # Shares can sit in different areas, so one Area cell would be a lie.
      test "a split row names every budget and its share, says Apportioned, and leaves Area blank" do
        @show_a.update!(area: create_reimbursements_area(name: "Cogito"))
        DatabaseStore.new.apportion_actual!(@payout.id, [
          { budget_id: @show_a.id, amount: BigDecimal("2500") },
          { budget_id: @show_b.id, amount: BigDecimal("1500") }
        ])

        row = csv_rows(DatabaseStore.new).first

        assert_equal "Cogito: Show A £2,500.00; Show B £1,500.00", row["Budget"]
        assert_equal "Apportioned", row["Status"]
        assert_nil row["Area"]
      end

      test "a row that paid several claims names each claim and its share" do
        budget = create_reimbursements_budget(name: "Props")
        claims = [ [ 41, "29.85" ], [ 42, "14.84" ] ].map do |number, amount|
          create_reimbursements_expense(auto_number: number, budget: budget, status: Status::SUBMITTED,
                                        amount: BigDecimal(amount), amount_excl_vat: BigDecimal(amount), receipt: false)
        end
        payment = create_reimbursements_eusa_actual(debit: BigDecimal("44.69"), narrative: "BACS PAYMENT")
        DatabaseStore.new.share_actual!(payment.id, claims.map { |c| { expense_id: c.id, amount: c.amount } })

        row = csv_rows(DatabaseStore.new).find { |r| r["Description"] == "BACS PAYMENT" }

        assert_equal "#41 £29.85; #42 £14.84", row["Linked expense"]
      end

      test "a row attached to one budget whole still names just that budget" do
        @payout.update!(budget: @show_a)

        assert_equal "Show A", csv_rows(DatabaseStore.new).first["Budget"]
      end
    end
  end
end
