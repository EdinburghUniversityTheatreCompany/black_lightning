require "application_system_test_case"

module Admin
  module Reimbursements
    # The budget-side area picker, clicked for real. A request-level test POSTs
    # straight to :update with whatever params the test author typed, so it
    # cannot see a form the browser itself fails to submit correctly — Task 7's
    # nested-fields shape could not deliver its params at all, and that was
    # only caught by a browser test clicking the real button. This proves the
    # <select> the browser actually renders carries the budget to its new area,
    # and that clearing it back to "— none —" detaches it.
    class BudgetsJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        login_as users(:member)
      end

      test "moves a budget to a different area from its own form in the browser" do
        create_reimbursements_area(name: "Cogito")
        create_reimbursements_area(name: "Improverts")
        budget = create_reimbursements_budget(name: "Cogito: Marketing",
                                              area: ::Reimbursements::Area.find_by!(name: "Cogito"))

        visit edit_admin_reimbursements_budget_path(budget.record_id)
        select "Improverts", from: "Area"
        click_on "Save budget"

        assert_text "Budget saved"
        assert_equal "Improverts", budget.reload.area.name
      end

      test "detaches a budget from its area from its own form in the browser" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        visit edit_admin_reimbursements_budget_path(budget.record_id)
        select "— none —", from: "Area"
        click_on "Save budget"

        assert_text "Budget saved"
        assert_nil budget.reload.area
      end
    end
  end
end
