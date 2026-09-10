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
        @termtime = create_reimbursements_cost_centre(
          key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
          receive_mailbox: "in@bedlamtheatre.invalid", send_mailbox: "out@bedlamtheatre.invalid"
        )
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
