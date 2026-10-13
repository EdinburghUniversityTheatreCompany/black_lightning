require "test_helper"

module Reimbursements
  module Exports
    ##
    # The Area and Cost centre columns. Budget names no longer carry an "Area: "
    # prefix, so Area is the only place the grouping survives in an export, and
    # an export is where two centres' figures are most easily added together by
    # hand.
    class GroupingColumnsTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      setup do
        @store = DatabaseStore.new
      end

      def cell(exporter, collection, header)
        rows = CSV.parse(exporter.to_csv(collection))
        rows[1][rows.first.index(header)]
      end

      test "Budgets name their own area and centre, and leave Area blank for an area-less line" do
        termtime = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Cogito")
        in_area = create_reimbursements_budget(name: "Marketing", area: area, cost_centre: termtime)
        loose = create_reimbursements_budget(name: "Contingency")

        assert_equal "Cogito", cell(Budgets.new(store: @store), [ in_area ], "Area")
        assert_equal "Bedlam Termtime", cell(Budgets.new(store: @store), [ in_area ], "Cost centre")
        assert_nil cell(Budgets.new(store: @store), [ loose ], "Area")
      end

      test "Expenses name the area, the bare budget and the centre through the claim's budget" do
        termtime = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Ergo")
        budget = create_reimbursements_budget(name: "Props", area: area, cost_centre: termtime)
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        assert_equal "Ergo", cell(Expenses.new(store: @store), [ expense ], "Area")
        assert_equal "Bedlam Termtime", cell(Expenses.new(store: @store), [ expense ], "Cost centre")
        # Bare: the sheet says the area in its own column.
        assert_equal "Props", cell(Expenses.new(store: @store), [ expense ], "Budget")
      end

      test "Expenses leave Area blank when the budget has no area or there is no budget" do
        no_area = create_reimbursements_expense(budget: create_reimbursements_budget(name: "Contingency"),
                                                receipt: false)
        no_budget = create_reimbursements_expense(receipt: false)

        assert_nil cell(Expenses.new(store: @store), [ no_area ], "Area")
        assert_nil cell(Expenses.new(store: @store), [ no_budget ], "Area")
        assert_nil cell(Expenses.new(store: @store), [ no_budget ], "Cost centre")
      end

      test "Actuals name the area through the Income budget and the centre on the row itself" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Box office", budget_type: "Income", area: area)
        actual = create_reimbursements_actual(budget: budget, debit: nil, credit: BigDecimal("500"),
                                              cost_centre: CostCentre.default)

        assert_equal "Cogito", cell(Actuals.new(store: @store), [ actual ], "Area")
        assert_equal CostCentre.default.name, cell(Actuals.new(store: @store), [ actual ], "Cost centre")
      end

      test "Actuals name the area through a linked expense's budget (the Expense-budget path)" do
        area = create_reimbursements_area(name: "Ergo")
        budget = create_reimbursements_budget(name: "Props", area: area)
        expense = create_reimbursements_expense(budget: budget, receipt: false)
        actual = create_reimbursements_actual(expense: expense)

        assert_equal "Ergo", cell(Actuals.new(store: @store), [ actual ], "Area")
      end

      test "Actuals leave Area blank when nothing they link to has an area" do
        loose = create_reimbursements_budget(name: "Contingency")
        actual = create_reimbursements_actual(budget: loose, debit: nil, credit: BigDecimal("50"))
        unlinked = create_reimbursements_actual(narrative: "Sundry")

        assert_nil cell(Actuals.new(store: @store), [ actual ], "Area")
        assert_nil cell(Actuals.new(store: @store), [ unlinked ], "Area")
      end

      test "Batches derive the centre from the expenses they hold" do
        termtime = create_second_reimbursements_cost_centre
        batch = Batch.create!(name: "Termtime run")
        budget = create_reimbursements_budget(name: "Termtime props", cost_centre: termtime)
        create_reimbursements_expense(budget: budget, batch: batch, status: Status::SUBMITTED,
                                      receipt: false)

        assert_equal "Bedlam Termtime", cell(Batches.new(store: DatabaseStore.new), [ batch ],
                                             "Cost centre")
      end

      test "Batches leave the centre blank rather than guessing for a mixed or empty batch" do
        batch = Batch.create!(name: "Empty run")

        assert_nil cell(Batches.new(store: DatabaseStore.new), [ batch ], "Cost centre")
      end

      # Budgets used to be the only scoped sheet, so the sheets did not add up.
      test "every workbook sheet reads the same cost-centre scope" do
        readers = Workbook::SHEETS.to_h

        assert_equal :expenses_for_cost_centre, readers[Expenses]
        assert_equal :eusa_actuals_for_cost_centre, readers[Actuals]
        assert_equal :budgets_with_actuals, readers[Budgets]
        assert_equal :batches_for_cost_centre, readers[Batches]
        # The one exception: a payee has no cost centre.
        assert_equal :people, readers[People]
      end
    end
  end
end
