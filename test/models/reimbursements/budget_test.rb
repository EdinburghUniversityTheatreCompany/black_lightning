require "test_helper"

module Reimbursements
  # Budget's computed figures: committed/paid sum amount_excl_vat,
  # current_forecast is the latest forecast, remaining/variance derive from it.
  class BudgetTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

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
      assert_equal BigDecimal("5"), budget.paid_portal_amount
    end

    test "current_forecast is the latest forecast amount, nil when none" do
      budget = build_budget
      assert_nil budget.current_forecast

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

    # --- Remaining falls back to the initial budget -------------------------

    test "remaining falls back to the initial budget when no forecast is logged" do
      budget = build_budget(initial_budget: 450)
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      assert_equal BigDecimal("350"), Budget.find(budget.id).remaining
    end

    test "a line with only an initial budget can read as over budget" do
      budget = build_budget(initial_budget: 100)
      add_expense(budget, status: Status::APPROVED, excl_vat: 140)

      fresh = Budget.find(budget.id)
      assert_not fresh.no_budget_set?
      assert_equal BigDecimal("-40"), fresh.remaining
      assert_predicate fresh, :over_budget?
    end

    test "remaining stays nil when nobody set a figure at all" do
      budget = build_budget
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      # Nil, never zero: a 0 reads as fully overspent.
      assert_nil Budget.find(budget.id).remaining
    end

    # An income plan is a target to raise, so target less spend is not money
    # left over.
    test "an income line does not take the initial-budget fallback" do
      income = build_budget(name: "Box office", budget_type: "Income", initial_budget: 800)

      assert_nil Budget.find(income.id).remaining
    end

    test "an income line with a forecast keeps the figure it always had" do
      income = build_budget(name: "Box office", budget_type: "Income", initial_budget: 800)
      income.forecasts.create!(amount: 900, date: Date.new(2026, 6, 1), reason: "revised")

      assert_equal BigDecimal("900"), Budget.find(income.id).remaining
    end

    # --- A £0 plan is unset, not a cap of nothing ---------------------------

    test "a line whose plan is exactly zero reads as having no budget set" do
      budget = build_budget(initial_budget: 0)
      add_expense(budget, status: Status::APPROVED, excl_vat: 200)

      fresh = Budget.find(budget.id)
      assert_predicate fresh, :no_budget_set?
      assert_nil fresh.remaining
      assert_not fresh.over_budget?, "a figure nobody filled in is not a cap that was blown"
      assert_nil fresh.variance
    end

    test "a zero FORECAST is unset too, not just a zero initial budget" do
      budget = build_budget(initial_budget: 500)
      budget.forecasts.create!(amount: 0, date: Date.new(2026, 6, 1), reason: "cancelled")

      assert_predicate Budget.find(budget.id), :no_budget_set?
    end

    # --- Variance -----------------------------------------------------------

    test "variance is zero, not blank, when the plan is still the initial budget" do
      budget = build_budget(initial_budget: 450)

      assert_equal BigDecimal("0"), Budget.find(budget.id).variance
    end

    test "variance is blank when no initial budget was agreed" do
      budget = build_budget
      budget.forecasts.create!(amount: 600, date: Date.new(2026, 6, 1), reason: "plan")

      assert_nil Budget.find(budget.id).variance
    end

    test "over_budget? when committed exceeds the forecast; income budgets never" do
      expense, income = %w[Expense Income].map do |type|
        budget = build_budget(budget_type: type)
        budget.forecasts.create!(amount: 10, date: Date.new(2026, 6, 1), reason: "small")
        add_expense(budget, status: Status::APPROVED, excl_vat: 40)
        Budget.find(budget.id)
      end

      assert_predicate expense, :over_budget?
      assert_equal BigDecimal("-30"), income.remaining
      assert_not income.over_budget?
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
      # On an income line the max would read as best-case income.
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

    # --- display_name --------------------------------------------------------

    test "display_name names the area a line belongs to" do
      area = Area.create!(name: "Cogito")
      assert_equal "Cogito: Marketing", build_budget(name: "Marketing", area: area).display_name
    end

    test "display_name is the bare name for a line in no area" do
      assert_equal "Props", build_budget.display_name
    end

    # display_name is load-bearing (import matching, receipt filenames, the BACS
    # reference), so the picker label must be a SEPARATE string.
    test "picker_label prefixes the cost centre without touching display_name" do
      centre = create_second_reimbursements_cost_centre(short_code: "BF")
      budget = build_budget(name: "Other", cost_centre: centre)

      assert_equal "BF - Other", budget.picker_label
      assert_equal "Other", budget.display_name
    end

    test "picker_label keeps the area composition" do
      centre = create_second_reimbursements_cost_centre(short_code: "BF")
      area = Area.create!(name: "Improverts", cost_centre: centre)
      budget = build_budget(name: "Other", cost_centre: centre, area: area)

      assert_equal "BF - Improverts: Other", budget.picker_label
    end

    test "picker_label is the display name when the budget has no cost centre" do
      # An unplaced line belongs to every centre, so there is none to name.
      budget = build_budget(name: "Other", cost_centre: nil)

      assert_equal "Other", budget.picker_label
    end

    # --- apportioned income --------------------------------------------------

    # One income line taking the whole of its own credit row.
    def split_income(name, credit)
      budget = create_reimbursements_budget(name: name, budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: credit)
      DatabaseStore.new.apportion_actual!(
        actual.id, [ { budget_id: budget.id, amount: BigDecimal(credit.to_s) } ]
      )
      budget
    end

    test "an income budget counts its share of an apportioned row" do
      budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
      other  = create_reimbursements_budget(name: "Show B", budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: 4000)
      DatabaseStore.new.apportion_actual!(actual.id, [
        { budget_id: budget.id, amount: BigDecimal("2500") },
        { budget_id: other.id,  amount: BigDecimal("1500") }
      ])

      assert_equal BigDecimal("2500"), budget.reload.eusa_actual_amount
      assert_equal BigDecimal("1500"), other.reload.eusa_actual_amount
    end

    # A split row has no budget_id, so the two sets never overlap; a row
    # linked whole is counted once.
    test "a fully linked row is counted once, not twice" do
      budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
      create_reimbursements_eusa_actual(credit: 900, budget: budget)

      assert_equal BigDecimal("900"), budget.reload.eusa_actual_amount
    end

    # An expense line totals through its expenses, so an allocation is not
    # income it earned.
    test "an expense budget's figure is untouched by allocations" do
      budget = create_reimbursements_budget(name: "Props", budget_type: "Expense")
      actual = create_reimbursements_eusa_actual(credit: 500)
      DatabaseStore.new.apportion_actual!(
        actual.id, [ { budget_id: budget.id, amount: BigDecimal("500") } ]
      )

      assert_equal 0, budget.reload.eusa_actual_amount
    end

    test "the overview does not query per budget for its allocations" do
      3.times { |i| split_income("Show #{i}", 100) }

      budgets = DatabaseStore.new.budgets_with_actuals
      queries = count_queries { budgets.each(&:eusa_actual_amount) }

      assert_equal 0, queries, "eusa_actual_amount must read preloaded allocations"
    end
  end
end
