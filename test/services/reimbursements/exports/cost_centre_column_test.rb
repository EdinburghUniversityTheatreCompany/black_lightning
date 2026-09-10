require "test_helper"

module Reimbursements
  module Exports
    ##
    # Every exporter that can name a cost centre carries the column, defined
    # ONCE in its HEADERS/#row — which is what makes the per-view "Download CSV"
    # and the combined workbook's matching sheet agree. An export is where two
    # centres' figures are most easily added together by hand, and a spreadsheet
    # with no centre column cannot be pivoted by one.
    class CostCentreColumnTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      setup do
        @fringe = CostCentre.default
        @termtime = create_second_reimbursements_cost_centre
        @store = DatabaseStore.new
      end

      def cell(exporter, collection, header)
        rows = CSV.parse(exporter.to_csv(collection))
        rows[1][rows.first.index(header)]
      end

      test "Expenses names the centre it reaches through the claim's budget" do
        budget = create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        assert_equal "Bedlam Termtime", cell(Expenses.new(store: @store), [ expense ], "Cost centre")
      end

      test "Expenses leaves the cell blank for a claim nothing places" do
        expense = create_reimbursements_expense(receipt: false)

        assert_nil cell(Expenses.new(store: @store), [ expense ], "Cost centre")
      end

      test "Actuals names the centre on the ledger row itself" do
        actual = EusaActual.create!(narrative: "Venue hire", debit: 10, cost_centre: @fringe)

        assert_equal @fringe.name, cell(Actuals.new(store: @store), [ actual ], "Cost centre")
      end

      test "Budgets names its own centre" do
        budget = create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)

        assert_equal "Bedlam Termtime", cell(Budgets.new(store: @store), [ budget ], "Cost centre")
      end

      test "Batches derives the centre from the expenses it holds" do
        batch = Batch.create!(name: "Termtime run")
        budget = create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        create_reimbursements_expense(budget: budget, batch: batch, status: Status::SUBMITTED,
                                      receipt: false)

        assert_equal "Bedlam Termtime", cell(Batches.new(store: DatabaseStore.new), [ batch ],
                                             "Cost centre")
      end

      test "Batches leaves the cell blank rather than guessing for a mixed or empty batch" do
        batch = Batch.create!(name: "Empty run")

        assert_nil cell(Batches.new(store: DatabaseStore.new), [ batch ], "Cost centre")
      end

      # Under ?cost_centre= the Budgets sheet used to be the only scoped one, so
      # the workbook carried claims, ledger rows and batches from other pots
      # beside budgets that could not account for them — the sheets no longer
      # added up to each other.
      test "every workbook sheet reads the same cost-centre scope" do
        scoped = DatabaseStore.new(cost_centre: @termtime)
        readers = Workbook::SHEETS.to_h { |exporter, method| [ exporter, method ] }

        assert_equal :expenses_for_cost_centre, readers[Expenses]
        assert_equal :eusa_actuals_for_cost_centre, readers[Actuals]
        assert_equal :budgets_with_actuals, readers[Budgets]
        assert_equal :batches_for_cost_centre, readers[Batches]
        # The one exception: a payee has no cost centre.
        assert_equal :people, readers[People]
        readers.each_value { |method| assert_respond_to scoped, method }
      end

      test "a scoped workbook carries only the selected centre's claims" do
        require "caxlsx"
        create_reimbursements_expense(receipt: false, description: "Fringe claim",
                                      budget: create_reimbursements_budget(name: "Fringe props",
                                                                           cost_centre: @fringe))
        create_reimbursements_expense(receipt: false, description: "Termtime claim",
                                      budget: create_reimbursements_budget(name: "Termtime props",
                                                                           cost_centre: @termtime))

        store = DatabaseStore.new(cost_centre: @termtime)
        rows = store.public_send(Workbook::SHEETS.first.last).map(&:description)

        assert_includes rows, "Termtime claim"
        assert_not_includes rows, "Fringe claim"
      end

      test "People has no cost-centre column, because a payee has no cost centre" do
        assert_not_includes People::HEADERS, "Cost centre"
      end

      test "a workbook sheet carries the same column as its CSV, from the one definition" do
        require "caxlsx"
        budget = create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        expense = create_reimbursements_expense(budget: budget, receipt: false)

        package = Axlsx::Package.new
        Expenses.new(store: DatabaseStore.new).add_sheet(package.workbook, [ expense ])

        sheet = package.workbook.worksheets.first
        headers = sheet.rows.first.cells.map(&:value)
        assert_includes headers, "Cost centre"
        assert_equal "Bedlam Termtime", sheet.rows[1].cells[headers.index("Cost centre")].value
      end
    end
  end
end
