require "test_helper"

module Reimbursements
  # The computed replacements for the Airtable rollups/formulas, confirmed
  # against the base schema export: committed/paid sum amount_excl_vat,
  # current_forecast is the latest forecast, remaining/variance derive from it.
  class BudgetTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def build_budget(**attrs)
      Budget.create!(name: "Props", **attrs)
    end

    def picker_cost_centre(key:, eusa_code:, short_code: "BF")
      CostCentre.create!(key: key, name: "Bedlam Fringe", eusa_code: eusa_code,
                         short_code: short_code,
                         receive_mailbox: "in-#{key}@example.com",
                         send_mailbox: "out-#{key}@example.com",
                         notification_email: "finance-#{key}@example.com")
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
      # No forecast AND no initial budget, so there is nothing to be left of.
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

    # --- Remaining falls back to the initial budget -------------------------
    #
    # Budget#remaining read the forecast alone, so a freshly imported financial
    # year showed "-" on every line under an area heading that printed a
    # Remaining of its own, and so did any line created by hand with an initial
    # figure. That is day one of every year, and it is what #projected_amount
    # (and Area#remaining) have always meant by "the plan".

    test "remaining falls back to the initial budget when no forecast is logged" do
      budget = build_budget(initial_budget: 450)
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      assert_equal BigDecimal("350"), Budget.find(budget.id).remaining
    end

    test "a line with only an initial budget can read as over budget" do
      budget = build_budget(initial_budget: 100)
      add_expense(budget, status: Status::APPROVED, excl_vat: 140)

      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("-40"), fresh.remaining
      assert_predicate fresh, :over_budget?
    end

    test "a logged forecast still wins over the initial figure" do
      budget = build_budget(initial_budget: 450)
      budget.forecasts.create!(amount: 600, date: Date.new(2026, 6, 1), reason: "revised")
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      assert_equal BigDecimal("500"), Budget.find(budget.id).remaining
    end

    test "remaining stays nil when nobody set a figure at all" do
      budget = build_budget
      add_expense(budget, status: Status::APPROVED, excl_vat: 100)

      # Nil, never zero: a 0 there reads as fully overspent, which is why
      # Area#remaining is nil in the same case.
      assert_nil Budget.find(budget.id).remaining
    end

    # An income line's plan is a target to RAISE and committed_amount is spend
    # somebody recorded against it, so "target less spend" is not money left
    # over. Falling it back onto the initial figure would put a number meaning
    # nothing on every income line.
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
    #
    # Mick's call. Production carries many termtime areas whose agreed total is
    # £0 with real spend against them; reading the 0 as a cap made every one of
    # them over budget, in red, for ever — a permanent false alarm, which is
    # how a real one stops being read.

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

    test "a real plan is untouched by the zero rule" do
      budget = build_budget(initial_budget: 100)
      add_expense(budget, status: Status::APPROVED, excl_vat: 140)

      fresh = Budget.find(budget.id)
      assert_not fresh.no_budget_set?
      assert_predicate fresh, :over_budget?
    end

    # --- Variance -----------------------------------------------------------
    #
    # With no forecast logged the plan IS the agreed figure, so the drift is
    # genuinely zero rather than unknown — a fact about the line. Blank stays
    # for the case that really is undefined: no initial budget to drift from.

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

    # --- display_name --------------------------------------------------------
    # The ONE composition every screen, reminder, email and receipt filename
    # reads. Stripping the "Area: " prefix left three live Fringe lines all
    # called "Marketing" on one nominal code.

    test "display_name names the area a line belongs to" do
      area = Area.create!(name: "Cogito")
      assert_equal "Cogito: Marketing", build_budget(name: "Marketing", area: area).display_name
    end

    test "display_name is the bare name for a line in no area" do
      assert_equal "Props", build_budget.display_name
    end

    test "display_name tells two identically-named lines apart" do
      cogito = build_budget(name: "Marketing", area: Area.create!(name: "Cogito"))
      improverts = build_budget(name: "Marketing", area: Area.create!(name: "Improverts"))

      assert_equal cogito.name, improverts.name
      assert_not_equal cogito.display_name, improverts.display_name
    end
    # display_name is load-bearing: BudgetImport.bare_name splits on its colon,
    # FilenameSanitizer builds receipt filenames from it, and ReviewSupport
    # .auto_payment_reference derives the BACS reference EUSA sees from it. The
    # picker label has to be a SEPARATE string, or prefixing a dropdown would
    # silently change the reference on every future payment.
    test "picker_label prefixes the cost centre without touching display_name" do
      centre = picker_cost_centre(key: "fringe-picker", eusa_code: "F40p")
      budget = build_budget(name: "Other", cost_centre: centre)

      assert_equal "BF - Other", budget.picker_label
      assert_equal "Other", budget.display_name
    end

    test "picker_label keeps the area composition" do
      centre = picker_cost_centre(key: "fringe-area", eusa_code: "F40a")
      area = Area.create!(name: "Improverts", cost_centre: centre)
      budget = build_budget(name: "Other", cost_centre: centre, area: area)

      assert_equal "BF - Improverts: Other", budget.picker_label
    end

    test "picker_label is the display name when the budget has no cost centre" do
      # An unplaced line is lenient-scoped into every centre's screens, so there
      # is no centre to name and a bare "- Other" would read as a missing one.
      budget = build_budget(name: "Other", cost_centre: nil)

      assert_equal "Other", budget.picker_label
    end

    # --- apportioned income --------------------------------------------------

    # One income line taking the whole of its own credit row. Extracted
    # because three tests below seed exactly this and jscpd gates at 0.
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

    # An apportioned row carries no budget_id (apportion_actual! clears it),
    # so the two sets never overlap. A row linked WHOLE must still be counted
    # exactly once.
    test "a fully linked row is counted once, not twice" do
      budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
      create_reimbursements_eusa_actual(credit: 900, budget: budget)

      assert_equal BigDecimal("900"), budget.reload.eusa_actual_amount
    end

    # An Expense line's figure totals through its EXPENSES, so an allocation
    # to one is not income it earned and must not appear in its rollup.
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

    # Negative control for the assertion above: without the preload the same
    # read really does cost a query per budget, so the zero is not vacuous.
    test "negative control: unpreloaded budgets DO query per budget" do
      3.times { |i| split_income("Unpreloaded #{i}", 100) }

      budgets = Budget.where(budget_type: "Income").to_a
      queries = count_queries { budgets.each(&:eusa_actual_amount) }

      assert_operator queries, :>=, 3,
                      "expected an unpreloaded read to cost a query per budget (got #{queries})"
    end
  end
end
