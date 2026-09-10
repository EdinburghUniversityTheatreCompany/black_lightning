require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The budget import wizard, clicked for real.
    #
    # A request test POSTs to #preview and #apply with whatever parameters it
    # likes, so it passes just as happily when the real form never sends them.
    # The wizard is stateless: the sheet survives into apply only through the
    # hidden fields the preview renders, and one of them (`canonical`) is what
    # tells apply the text is this class's OWN escaped output rather than
    # something the operator typed.
    class BudgetImportJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      HEADERS = ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t").freeze

      setup do
        grant_finance_permission(users(:member))
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        @cost_centre = ::Reimbursements::CostCentre.default
        login_as users(:member)
      end

      # TSV_HEADERS leads with the two AREA columns, so a row stating only a
      # budget line has to leave them blank — otherwise every cell shifts one
      # column left and the sheet imports a budget named "Expense". Padded
      # here rather than in each row so the call sites stay readable.
      def sheet(*rows) = ([ HEADERS ] + rows.map { |row| "\t\t#{row}" }).join("\n")

      def area_sheet(*rows)
        ([ "Area\tBudget\tNominal code\tType\tAmount" ] + rows).join("\n")
      end

      # A budget name is what an existing line is MATCHED on, so rewriting a
      # backslash sequence in it is silent corruption of the key. Only a browser
      # proves the marker is really posted: the request test hands apply the
      # parameter itself.
      test "a backslash the operator typed survives preview into apply" do
        visit admin_reimbursements_budget_import_path

        fill_in "Paste the sheet", with: sheet("Costume\\next week\t4000\tExpense\t1200\t\t")
        click_on "Preview import"

        assert_text "Costume\\next week"
        assert_selector "input[name='canonical']", visible: false

        assert_difference -> { ::Reimbursements::Budget.count }, +1 do
          click_on "Import 1 new budget"
          assert_text "Imported into Fringe 2027"
        end

        assert_equal "Costume\\next week", ::Reimbursements::Budget.sole.name
      end

      # Only a browser proves the ticks reach apply AT ALL: the request test
      # hands #apply the parameter itself, so it passes just as happily when
      # the form renders no checkbox — and a `name[]` checkbox array is
      # exactly where Rack's parsing has bitten this wizard's siblings.
      test "a ticked re-home moves its line and an unticked one is left alone" do
        improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                                financial_year: @year)
        cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)
        marketing = create_reimbursements_budget(name: "Cogito: Marketing", area: improverts,
                                                 initial_budget: 400, cost_centre: @cost_centre,
                                                 financial_year: @year)
        set = create_reimbursements_budget(name: "Cogito: Set", area: improverts,
                                           initial_budget: 500, cost_centre: @cost_centre,
                                           financial_year: @year)

        visit admin_reimbursements_budget_import_path

        fill_in "Paste the sheet", with: area_sheet(
          "Cogito\tCogito: Marketing\t432320\tExpense\t400",
          "Cogito\tCogito: Set\t432320\tExpense\t500"
        )
        click_on "Preview import"

        assert_checked_field "re-home-#{marketing.record_id}"
        uncheck "re-home-#{set.record_id}"

        click_on "Import 2 moved lines"
        assert_text "Imported into Fringe 2027"

        assert_equal cogito.id, marketing.reload.area_id
        assert_equal improverts.id, set.reload.area_id
      end
    end
  end
end
