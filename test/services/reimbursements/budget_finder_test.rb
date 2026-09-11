require "test_helper"

module Reimbursements
  class BudgetFinderTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @centre = reimbursements_cost_centres(:fringe)
      @year = FinancialYear.create!(label: "Fringe 2026", active: true)
      @area = create_reimbursements_area(name: "Cogito", financial_year: @year, cost_centre: @centre)
      create_reimbursements_nominal_code(code: "432320", cost_centre: @centre, label: "Marketing")
    end

    # Named for what it buys rather than for the code, so only the CODE pass can
    # find it: a line called "Marketing" is found by the label pass too, and a
    # test seeded that way passes with the code lookup gone.
    test "an existing line under the same area and code is found, not duplicated" do
      existing = line(name: "Correx boards", nominal_code: "432320")

      found = find_or_create

      assert_equal existing.id, found.id
      assert_equal 1, @area.budgets.where(nominal_code: "432320").count
    end

    test "a created line carries no agreed figure and is named from the code's label" do
      created = find_or_create

      assert_nil created.initial_budget, "nobody agreed this figure"
      assert_nil created.remaining
      assert_equal @area.id, created.area_id
      assert_equal "Marketing", created.name
      assert_equal "432320", created.nominal_code
    end

    test "two candidate lines raise rather than resolving to one" do
      line(name: "Marketing", nominal_code: "432320")
      line(name: "Print", nominal_code: "432320")

      error = assert_raises(BudgetFinder::AmbiguousError) { find_or_create }

      assert_match "Marketing", error.message
      assert_match "Print", error.message
      assert_equal 2, @area.budgets.count
    end

    test "a line named for the code is found under both spellings, within its own area" do
      prefixed = line(name: "Cogito: Marketing", nominal_code: "")
      other_area = create_reimbursements_area(name: "Last Orders", financial_year: @year,
                                              cost_centre: @centre)
      bare = line(name: "Marketing", nominal_code: "", area: other_area)

      assert_equal prefixed.id, find_or_create.id
      assert_equal bare.id, find_or_create(area: other_area).id
      assert_equal 2, Budget.where(area_id: [ @area.id, other_area.id ]).count
    end

    test "a line named for the code but carrying another code raises rather than being re-pointed" do
      line(name: "Marketing", nominal_code: "431000")

      error = assert_raises(BudgetFinder::AmbiguousError) { find_or_create }

      assert_match "431000", error.message
      assert_equal 1, @area.budgets.count
    end

    test "a code this centre does not list cannot name a new line" do
      assert_raises(BudgetFinder::UnknownCodeError) { find_or_create(nominal_code: "999999") }

      assert_equal 0, @area.budgets.count
    end

    test "a retired code still finds its line but never creates one" do
      retired = create_reimbursements_nominal_code(code: "431000", cost_centre: @centre,
                                                   label: "Print", active: false)
      existing = line(name: retired.label, nominal_code: retired.code)

      assert_equal existing.id, find_or_create(nominal_code: "431000").id

      existing.destroy!
      assert_raises(BudgetFinder::RetiredCodeError) { find_or_create(nominal_code: "431000") }
      assert_equal 0, @area.budgets.count
    end

    test "a deactivated line on the code is found rather than duplicated beside" do
      existing = line(name: "Marketing", nominal_code: "432320", active: false)

      assert_equal existing.id, find_or_create.id
      assert_equal 1, @area.budgets.count
    end

    test "a blank code is refused rather than matching every uncoded line" do
      line(name: "Set", nominal_code: "")

      assert_raises(ArgumentError) { find_or_create(nominal_code: " ") }
    end

    test "the created line takes its area's centre and year, not the caller's" do
      other_centre = create_second_reimbursements_cost_centre
      other_year = FinancialYear.create!(label: "Fringe 2027")

      created = BudgetFinder.find_or_create!(area: @area, nominal_code: "432320",
                                             financial_year: other_year, cost_centre: other_centre)

      assert_equal @centre.id, created.cost_centre_id
      assert_equal @year.id, created.financial_year_id
    end

    # The double-submitted form, at the level the guard lives: both requests
    # pass their own read (nothing exists) and both call the store. The second
    # call must find what the first created rather than create a second line —
    # the property the re-taken lookup inside the transaction exists for, which
    # a single call cannot demonstrate.
    test "a second store call for the same (area, code) finds the first one's line" do
      store = Reimbursements.build_store
      first = store.find_or_create_budget_for_area!(**store_args)
      second = Reimbursements.build_store.find_or_create_budget_for_area!(**store_args)

      assert_equal first.id, second.id
      assert_equal 1, @area.budgets.count
    end

    private

    def line(name:, nominal_code:, area: @area, active: true)
      create_reimbursements_budget(name: name, nominal_code: nominal_code, area: area,
                                   active: active, financial_year: @year, cost_centre: @centre)
    end

    def find_or_create(area: @area, nominal_code: "432320")
      BudgetFinder.find_or_create!(area: area, nominal_code: nominal_code,
                                   financial_year: @year, cost_centre: @centre)
    end

    def store_args
      { area_id: @area.id, nominal_code: "432320", name: "Marketing",
        cost_centre: @centre, financial_year: @year }
    end
  end
end
