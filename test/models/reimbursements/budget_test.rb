require "test_helper"

module Reimbursements
  # The computed replacements for the Airtable rollups/formulas, confirmed
  # against the base schema export: committed/paid sum amount_excl_vat,
  # current_forecast is the latest forecast, remaining/variance derive from it.
  class BudgetTest < ActiveSupport::TestCase
    def build_budget(**attrs)
      Budget.create!(name: "Props", **attrs)
    end

    def add_expense(budget, status:, excl_vat:)
      Expense.create!(budget: budget, status: status, amount: excl_vat * 1.2r,
                      amount_excl_vat: excl_vat, description: "x")
    end

    test "committed_amount sums excl-VAT amounts of Approved, Submitted and Paid" do
      budget = build_budget
      add_expense(budget, status: Status::APPROVED, excl_vat: 10)
      add_expense(budget, status: Status::SUBMITTED, excl_vat: 20)
      add_expense(budget, status: Status::PAID, excl_vat: 5)
      add_expense(budget, status: Status::PENDING, excl_vat: 100)
      add_expense(budget, status: Status::REJECTED, excl_vat: 100)

      assert_equal BigDecimal("35"), budget.committed_amount
      assert_equal BigDecimal("5"), budget.total_paid
    end

    test "current_forecast is the latest forecast amount, nil when none" do
      budget = build_budget
      assert_nil budget.current_forecast
      assert_nil budget.remaining

      budget.forecasts.create!(amount: 100, date: Date.new(2026, 5, 1), reason: "initial")
      budget.forecasts.create!(amount: 150, date: Date.new(2026, 6, 1), reason: "revised")
      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("150"), fresh.current_forecast
    end

    test "remaining and variance derive from the current forecast" do
      budget = build_budget(initial_budget: 120)
      budget.forecasts.create!(amount: 150, date: Date.new(2026, 6, 1), reason: "revised")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)

      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("110"), fresh.remaining
      assert_equal BigDecimal("30"), fresh.variance
      assert_not fresh.over_budget?
    end

    test "over_budget? when committed exceeds the forecast; income budgets never" do
      budget = build_budget
      budget.forecasts.create!(amount: 10, date: Date.new(2026, 6, 1), reason: "small")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)
      assert Budget.find(budget.id).over_budget?

      income = build_budget(name: "Grant", budget_type: "Income")
      income.forecasts.create!(amount: 0, date: Date.new(2026, 6, 1), reason: "n/a")
      assert_not Budget.find(income.id).over_budget?
    end

    test "over_initial_budget? flags committed past the initial figure" do
      budget = build_budget(initial_budget: 30)
      budget.forecasts.create!(amount: 100, date: Date.new(2026, 6, 1), reason: "revised up")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)

      fresh = Budget.find(budget.id)
      assert_not fresh.over_budget?
      assert fresh.over_initial_budget?
    end

    test "owner_ids returns People record-id strings via the join table" do
      budget = build_budget
      alice = Person.create!(name: "Alice", email: "alice-owner@example.com")
      bob = Person.create!(name: "Bob", email: "bob-owner@example.com")
      budget.owners << alice << bob

      assert_equal [ alice.record_id, bob.record_id ].sort, budget.owner_ids.sort
      assert_kind_of String, budget.owner_ids.first
    end

    test "income? mirrors the PORO" do
      assert build_budget(name: "G", budget_type: "Income").income?
      assert_not build_budget(name: "E").income?
    end

    # --- Overview rollups --------------------------------------------------

    test "projected_amount is the current forecast, falling back to the initial budget" do
      # No forecast, no initial → nil (not tracked).
      assert_nil build_budget.projected_amount

      # Initial only → initial.
      assert_equal BigDecimal("500"), build_budget(initial_budget: 500).projected_amount

      # Forecast wins over the initial figure.
      budget = build_budget(initial_budget: 500)
      budget.forecasts.create!(amount: 650, date: Date.new(2026, 6, 1), reason: "revised")
      assert_equal BigDecimal("650"), Budget.find(budget.id).projected_amount
    end

    test "paid_portal_amount is the portal total_paid" do
      budget = build_budget
      add_expense(budget, status: Status::PAID, excl_vat: 40)
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("40"), fresh.paid_portal_amount
      assert_equal fresh.total_paid, fresh.paid_portal_amount
    end

    test "eusa_actual_amount nets linked EUSA debits and credits for an Expense budget" do
      budget = build_budget
      paid = add_expense(budget, status: Status::PAID, excl_vat: 40)
      approved = add_expense(budget, status: Status::APPROVED, excl_vat: 100)
      EusaActual.create!(expense: paid, nominal_code: "4000", debit: BigDecimal("42.50"))
      EusaActual.create!(expense: approved, nominal_code: "4000", debit: BigDecimal("7.50"))
      # A credit note linked to the same expense (a refund) reduces what the
      # line actually cost: 50 - 5 = 45.
      EusaActual.create!(expense: paid, nominal_code: "4000", credit: BigDecimal("5"))
      # An actual on an unrelated expense/budget is ignored.
      other = build_budget(name: "Other")
      EusaActual.create!(expense: add_expense(other, status: Status::PAID, excl_vat: 9),
                         nominal_code: "9999", debit: BigDecimal("99"))

      assert_equal BigDecimal("45"), Budget.find(budget.id).eusa_actual_amount
    end

    test "a supplier refund on an expense budget reduces its EUSA actual" do
      budget = build_budget
      paid = add_expense(budget, status: Status::PAID, excl_vat: 900)
      EusaActual.create!(expense: paid, nominal_code: "4000", debit: BigDecimal("900"))
      EusaActual.create!(expense: paid, nominal_code: "4000", credit: BigDecimal("300"),
                         narrative: "Supplier refund")

      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("600"), fresh.eusa_actual_amount
      # expected_outturn reads the netted figure too:
      # max(projected nil, committed 900, paid 900, eusa 600) = 900, not 1200.
      assert_equal BigDecimal("900"), fresh.expected_outturn
    end

    test "a row carrying both a debit and a credit nets on one line" do
      budget = build_budget
      paid = add_expense(budget, status: Status::PAID, excl_vat: 100)
      EusaActual.create!(expense: paid, nominal_code: "4000", debit: BigDecimal("100"),
                         credit: BigDecimal("40"))

      assert_equal BigDecimal("60"), Budget.find(budget.id).eusa_actual_amount
    end

    test "eusa_actual_amount ignores offsetting legs linked to an expense" do
      budget = build_budget
      paid = add_expense(budget, status: Status::PAID, excl_vat: 4200)
      accrual = EusaActual.create!(expense: paid, nominal_code: "4000",
                                   debit: BigDecimal("4200"),
                                   reconciliation_status: EusaActual::STATUS_OFFSET)
      # Only the debit leg is linked to the expense; the reversal is not. Netting
      # alone would still show 4,200 of spend that was reversed, so an offsetting
      # leg is dropped outright.
      EusaActual.create!(nominal_code: "4000", credit: BigDecimal("4200"),
                         reconciliation_status: EusaActual::STATUS_OFFSET,
                         offset_of_id: accrual.id)

      assert_equal 0, Budget.find(budget.id).eusa_actual_amount
    end

    test "eusa_actual_amount nets direct credits against debits for an Income budget" do
      income = build_budget(name: "Ticket income", budget_type: "Income")
      EusaActual.create!(budget: income, nominal_code: "8000", credit: BigDecimal("300"))
      EusaActual.create!(budget: income, nominal_code: "8000", credit: BigDecimal("120"))
      # A debit booked against an income line is income handed back (a refunded
      # ticket), so it reduces the income: 420 - 10 = 410.
      EusaActual.create!(budget: income, nominal_code: "8000", debit: BigDecimal("10"))

      assert_equal BigDecimal("410"), Budget.find(income.id).eusa_actual_amount
    end

    test "pipeline_amount sums excl-VAT amounts of Pending expenses only" do
      budget = build_budget
      add_expense(budget, status: Status::PENDING, excl_vat: 30)
      add_expense(budget, status: Status::PENDING, excl_vat: 20)
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)
      add_expense(budget, status: Status::DRAFT, excl_vat: 5)

      assert_equal BigDecimal("50"), Budget.find(budget.id).pipeline_amount
    end

    test "expected_outturn is the max of projected, committed, paid and EUSA actual" do
      # Projected (forecast) 100, committed 150 (Approved) → committed wins.
      budget = build_budget(initial_budget: 80)
      budget.forecasts.create!(amount: 100, date: Date.new(2026, 6, 1), reason: "plan")
      add_expense(budget, status: Status::APPROVED, excl_vat: 150)
      assert_equal BigDecimal("150"), Budget.find(budget.id).expected_outturn

      # EUSA actual can exceed everything else and then drives the number.
      paid = add_expense(budget, status: Status::PAID, excl_vat: 20)
      EusaActual.create!(expense: paid, nominal_code: "4000", debit: BigDecimal("400"))
      assert_equal BigDecimal("400"), Budget.find(budget.id).expected_outturn
    end

    test "expected_outturn is blank for an Income budget" do
      # "The greater of the projection and what's already been spent" is a
      # worst-case cost. On an income line the same max reads as BEST-case
      # income, the opposite direction, so it would be actively misleading:
      # blank instead of a wrong number.
      income = build_budget(name: "Ticket income", budget_type: "Income", initial_budget: 8000)
      EusaActual.create!(budget: income, nominal_code: "8000", credit: BigDecimal("3000"))

      fresh = Budget.find(income.id)
      assert_nil fresh.expected_outturn
      # The underlying figures are still reported.
      assert_equal BigDecimal("8000"), fresh.projected_amount
      assert_equal BigDecimal("3000"), fresh.eusa_actual_amount
    end

    test "expected_outturn is zero when a budget has no plan and no activity" do
      # projected is nil but committed/paid/eusa default to 0, so the compacted
      # max is 0 (never below reality, and reality here is "nothing yet").
      assert_equal 0, build_budget.expected_outturn
    end
  end
end
