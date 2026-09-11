require "test_helper"

module Reimbursements
  module Exports
    ##
    # Every export that can name an area carries the column, defined ONCE in
    # its HEADERS/#row — Task 6 stripped the "Area: " prefix from budget
    # names, so the area name is now the only place the grouping survives in
    # an export; without this column that information is simply gone.
    class AreaColumnTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      setup do
        @store = DatabaseStore.new
      end

      def cell(exporter, collection, header)
        rows = CSV.parse(exporter.to_csv(collection))
        rows[1][rows.first.index(header)]
      end

      test "Budgets names the line's area, and leaves an area-less line blank" do
        area = create_reimbursements_area(name: "Cogito")
        in_area = create_reimbursements_budget(name: "Marketing", area: area)
        loose = create_reimbursements_budget(name: "Contingency")

        assert_equal "Cogito", cell(Budgets.new(store: @store), [ in_area ], "Area")
        assert_nil cell(Budgets.new(store: @store), [ loose ], "Area")
      end

      test "Expenses names the area it reaches through the claim's budget" do
        area = create_reimbursements_area(name: "Ergo")
        budget = create_reimbursements_budget(name: "Props", area: area)
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        assert_equal "Ergo", cell(Expenses.new(store: @store), [ expense ], "Area")
      end

      # The Budget column is read off the same preloaded map as the Area beside
      # it, so the two cannot come from different Budget objects — and it stays
      # the BARE name, because the sheet says the area in its own column.
      test "Expenses names the budget from the same map, bare" do
        area = create_reimbursements_area(name: "Ergo")
        budget = create_reimbursements_budget(name: "Props", area: area)
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        assert_equal "Props", cell(Expenses.new(store: @store), [ expense ], "Budget")
      end

      test "Expenses leaves the cell blank for a claim whose budget has no area" do
        budget = create_reimbursements_budget(name: "Contingency")
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        assert_nil cell(Expenses.new(store: @store), [ expense ], "Area")
      end

      test "Expenses leaves the cell blank for a claim with no budget at all" do
        expense = create_reimbursements_expense(receipt: false)

        assert_nil cell(Expenses.new(store: @store), [ expense ], "Area")
      end

      test "Actuals names the area it reaches directly (the Income-budget path)" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Box office", budget_type: "Income", area: area)
        actual = create_reimbursements_actual(budget: budget, debit: nil, credit: BigDecimal("500"))

        assert_equal "Cogito", cell(Actuals.new(store: @store), [ actual ], "Area")
      end

      test "Actuals names the area it reaches through a linked expense's budget (the Expense-budget path)" do
        area = create_reimbursements_area(name: "Ergo")
        budget = create_reimbursements_budget(name: "Props", area: area)
        expense = create_reimbursements_expense(budget: budget, receipt: false)
        actual = create_reimbursements_actual(expense: expense)

        assert_equal "Ergo", cell(Actuals.new(store: @store), [ actual ], "Area")
      end

      test "Actuals leaves the cell blank when nothing it links to has an area" do
        loose = create_reimbursements_budget(name: "Contingency")
        actual = create_reimbursements_actual(budget: loose, debit: nil, credit: BigDecimal("50"))
        unlinked = create_reimbursements_actual(narrative: "Sundry")

        assert_nil cell(Actuals.new(store: @store), [ actual ], "Area")
        assert_nil cell(Actuals.new(store: @store), [ unlinked ], "Area")
      end

      test "People has no Area column, because a payee has no area" do
        assert_not_includes People::HEADERS, "Area"
      end

      test "Batches has no Area column, because a batch spans several claims and shows" do
        assert_not_includes Batches::HEADERS, "Area"
      end

      test "Area is appended after Cost centre, so a saved formula keeps its column" do
        assert_equal "Area", Budgets::HEADERS.last
        assert_equal "Cost centre", Budgets::HEADERS[-2]
        assert_equal "Area", Expenses::HEADERS.last
        assert_equal "Cost centre", Expenses::HEADERS[-2]
        assert_equal "Area", Actuals::HEADERS.last
        assert_equal "Cost centre", Actuals::HEADERS[-2]
      end

      test "a workbook sheet carries the same Area cell as its CSV, from the one definition" do
        require "caxlsx"
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Marketing", area: area)

        package = Axlsx::Package.new
        Budgets.new(store: DatabaseStore.new).add_sheet(package.workbook, [ budget ])

        sheet = package.workbook.worksheets.first
        headers = sheet.rows.first.cells.map(&:value)
        assert_includes headers, "Area"
        assert_equal "Cogito", sheet.rows[1].cells[headers.index("Area")].value
      end

      test "the Actuals workbook sheet carries the same Area cell as its CSV, from the one definition" do
        require "caxlsx"
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Box office", budget_type: "Income", area: area)
        actual = create_reimbursements_actual(budget: budget, debit: nil, credit: BigDecimal("500"))

        package = Axlsx::Package.new
        Actuals.new(store: DatabaseStore.new).add_sheet(package.workbook, [ actual ])

        sheet = package.workbook.worksheets.first
        headers = sheet.rows.first.cells.map(&:value)
        assert_includes headers, "Area"
        assert_equal "Cogito", sheet.rows[1].cells[headers.index("Area")].value
      end

      # An area named like a plain number must survive as literal text in the
      # xlsx sheet, the same guard Base#cell_types gives a nominal code — an
      # unguarded numeric-looking string would arrive coerced to a number.
      test "a numeric-looking area name stays literal text in the workbook" do
        require "caxlsx"
        area = create_reimbursements_area(name: "2026")
        budget = create_reimbursements_budget(name: "Marketing", area: area)

        package = Axlsx::Package.new
        Budgets.new(store: DatabaseStore.new).add_sheet(package.workbook, [ budget ])

        sheet = package.workbook.worksheets.first
        headers = sheet.rows.first.cells.map(&:value)
        cell = sheet.rows[1].cells[headers.index("Area")]
        assert_equal "2026", cell.value
        assert_equal :string, cell.type
      end
    end
  end
end
