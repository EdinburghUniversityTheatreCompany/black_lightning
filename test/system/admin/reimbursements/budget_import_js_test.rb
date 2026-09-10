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

      def sheet(*rows) = ([ HEADERS ] + rows).join("\n")

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
    end
  end
end
