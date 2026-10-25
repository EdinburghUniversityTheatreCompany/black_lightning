require "test_helper"

module Reimbursements
  # EUSA does not always pay one claim with one ledger row: it combines a payee's claims into one
  # payment (one row, several claims) and splits a claim across rows (several rows, one claim).
  class SplitPaymentsTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def store = @store ||= DatabaseStore.new

    setup do
      @props = create_reimbursements_budget(name: "Props", nominal_code: "432980")
      @costumes = create_reimbursements_budget(name: "Costumes", nominal_code: "432980")
    end

    def claim(amount, budget: @props, status: Status::SUBMITTED, **attrs)
      create_reimbursements_expense(budget: budget, status: status, amount: BigDecimal(amount),
                                    amount_excl_vat: BigDecimal(amount), receipt: false, **attrs)
    end

    def row(debit, date: Date.new(2026, 7, 29))
      create_reimbursements_eusa_actual(nominal_code: "432980", narrative: "BACS PAYMENT",
                                        debit: BigDecimal(debit), date: date)
    end

    def shares_for(*pairs) = pairs.map { |expense, amount| { expense_id: expense.id, amount: BigDecimal(amount) } }

    # --- One row paying several claims ----------------------------------

    test "sharing a row settles each claim on the row's date and counts each share on its own budget" do
      first = claim("29.85")
      second = claim("14.84", budget: @costumes)
      payment = row("44.69")

      store.share_actual!(payment.id, shares_for([ first, "29.85" ], [ second, "14.84" ]))

      [ first, second ].each do |expense|
        expense.reload
        assert_equal Status::PAID, expense.status
        assert_equal Date.new(2026, 7, 29), expense.payment_confirmed_date
      end
      payment.reload
      assert_not payment.needs_attention?, "a shared row is placed"
      assert_not payment.convertible_to_expense?, "converting it would count the spend twice"
      assert_equal BigDecimal("29.85"), @props.reload.eusa_actual_amount
      assert_equal BigDecimal("14.84"), @costumes.reload.eusa_actual_amount
      preloaded = store.budgets_with_actuals.index_by(&:id)
      assert_equal BigDecimal("29.85"), preloaded[@props.id].eusa_actual_amount, "the preloaded figure agrees"
    end

    test "sharing refuses, and writes nothing, unless at least two settleable UK claims take exactly the row" do
      settled = claim("14.84", status: Status::PAID, payment_confirmed_date: Date.new(2026, 7, 1))
      international = claim("14.84", payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
                                     foreign_amount: BigDecimal("17"), foreign_currency: Expense::CURRENCY_EUR)
      first = claim("29.85")
      second = claim("14.84")
      payment = row("44.69")
      {
        "parts short of the row" => shares_for([ first, "29.85" ], [ second, "14.00" ]),
        "one claim" => shares_for([ first, "44.69" ]),
        "a claim already settled" => shares_for([ first, "29.85" ], [ settled, "14.84" ]),
        "an international claim" => shares_for([ first, "29.85" ], [ international, "14.84" ])
      }.each do |label, shares|
        assert_raises(DatabaseStore::ShareRefusedError, label) { store.share_actual!(payment.id, shares) }
        assert_empty ClaimShare.all, label
        assert_equal Status::SUBMITTED, first.reload.status, label
      end
    end

    test "a shared claim is settled: no other row may settle it and Reconcile no longer offers it" do
      first = claim("29.85")
      second = claim("14.84")
      store.share_actual!(row("44.69").id, shares_for([ first, "29.85" ], [ second, "14.84" ]))

      assert_not_includes store.matchable_expenses.map(&:id), first.id
      assert_raises(DatabaseStore::NotSettleableError) do
        store.settle_expense_from_actual!(row("29.85").id, first.id, payment_date: Date.new(2026, 8, 1))
      end
    end

    test "unsharing returns each claim to Submitted and the row to needing attention" do
      first = claim("29.85")
      second = claim("14.84")
      payment = row("44.69")
      store.share_actual!(payment.id, shares_for([ first, "29.85" ], [ second, "14.84" ]))

      store.unshare_actual!(payment.id)

      assert_empty ClaimShare.all
      [ first, second ].each do |expense|
        assert_equal Status::SUBMITTED, expense.reload.status
        assert_nil expense.payment_confirmed_date
      end
      assert payment.reload.needs_attention?
    end

    # --- Several rows paying one claim ----------------------------------

    def settled_by(first_row, expense)
      store.settle_expense_from_actual!(first_row.id, expense.id, payment_date: first_row.date)
    end

    test "a further row adds to a claim another row settled, and the budget counts both" do
      expense = claim("76.18")
      settled_by(row("14.98"), expense)
      part = row("61.19")

      store.add_part_payment!(part.id, expense.id)

      assert_equal expense.id, part.reload.expense_id
      assert_equal Status::PAID, expense.reload.status
      assert_equal BigDecimal("76.17"), @props.reload.eusa_actual_amount
    end

    # A second full payment is EUSA paying twice; hiding it under the claim would lose the money.
    test "a part is refused when the parts would come to more than the claim, or on an unsettled claim" do
      paid_twice = claim("246.00")
      settled_by(row("246.00"), paid_twice)
      unsettled = claim("50.00")
      second = row("246.00")

      assert_raises(DatabaseStore::PartRefusedError) { store.add_part_payment!(second.id, paid_twice.id) }
      assert_raises(DatabaseStore::PartRefusedError) { store.add_part_payment!(row("10.00").id, unsettled.id) }
      assert second.reload.needs_attention?, "the second payment stays on the ledger to be seen"
    end

    test "unlinking one part leaves the claim Paid; unlinking the last returns it to Submitted" do
      expense = claim("76.18")
      first = row("14.98")
      settled_by(first, expense)
      part = row("61.19")
      store.add_part_payment!(part.id, expense.id)

      store.unlink_actual_from_expense!(part.id)
      assert_equal Status::PAID, expense.reload.status, "another row still pays it"

      store.unlink_actual_from_expense!(first.id)
      assert_equal Status::SUBMITTED, expense.reload.status
      assert_nil expense.payment_confirmed_date
    end
  end
end
