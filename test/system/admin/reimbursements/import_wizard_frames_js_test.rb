require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # Every way OUT of an import wizard, clicked. A link inside the wizard's
    # Turbo Frame navigates the frame, so one to a page without that frame
    # shows "Content missing", which no request test can see.
    class ImportWizardFramesJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        login_as users(:member)
      end

      # Clicks +link+ from +path+ and asserts the whole page navigated.
      def assert_escapes_frame(path, link, expected)
        visit path
        click_on link

        assert_no_text "Content missing"
        assert_text expected
      end

      test "the budget import's back link leaves the frame" do
        assert_escapes_frame admin_reimbursements_budget_import_path, "All budgets", "New budget"
      end

      test "the budget import's Cancel leaves the frame for the page's year and cost centre" do
        termtime = create_second_reimbursements_cost_centre
        assert_escapes_frame admin_reimbursements_budget_import_path(year: @year.key, cost_centre: termtime.key),
                             "Cancel", "New budget"

        assert_current_path admin_reimbursements_budgets_path(year: @year.key, cost_centre: termtime.key)
      end

      test "the expense import's back link leaves the frame" do
        assert_escapes_frame admin_reimbursements_expense_import_path, "All expenses", "Filter & search"
      end
    end
  end
end
