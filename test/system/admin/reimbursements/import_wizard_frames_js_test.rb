require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # Every way OUT of an import wizard, clicked.
    #
    # Both wizards live in one Turbo Frame, because Turbo Drive discards a
    # non-redirect response to a form POST and a stateless wizard cannot
    # redirect. The cost of that is invisible to every request test: a link
    # inside a frame navigates THE FRAME, so a link to a page with no matching
    # frame replaces the wizard with Turbo's "Content missing" and dead-ends the
    # operator. Every escape link shipped that way until this test.
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
        assert_escapes_frame admin_reimbursements_budget_import_path, "All budgets", "Budget overview"
      end

      test "the expense import's back link leaves the frame" do
        assert_escapes_frame admin_reimbursements_expense_import_path, "All expenses", "Filter & search"
      end
    end
  end
end
