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

      # M8, clicked. The owners fieldset and the area picker are one control
      # between them: a request test posts whatever params its author typed, so
      # it can assert the server REFUSES owner_ids alongside an area but cannot
      # see whether a browser sends them at all. A disabled fieldset submits
      # none of its controls, which is what keeps the operator away from that
      # refusal — and what leaves the budget's own owner rows untouched instead
      # of synced to an empty list.
      test "choosing an area on the new-budget form takes the owners list away" do
        create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        area = create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path
        check "Alice Owner"
        select "Cogito", from: "Area"

        assert_text "it takes the area's owners"
        fill_in "Name", with: "Marketing"
        fill_in "Nominal code", with: "432320"
        click_on "Create budget"

        assert_text "Budget created"
        budget = ::Reimbursements::Budget.find_by!(name: "Marketing")
        assert_equal area, budget.area
        assert_empty budget.own_owners,
                     "the browser must send no owner_ids at all for a line going into an area"
      end

      # The other half of the same control: with no area chosen the list is the
      # live one, so a green test above cannot be a fieldset that never enables.
      test "a line in no area still saves the owners ticked on the same form" do
        person = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path
        check "Alice Owner"
        fill_in "Name", with: "Contingency"
        fill_in "Nominal code", with: "432340"
        click_on "Create budget"

        assert_text "Budget created"
        budget = ::Reimbursements::Budget.find_by!(name: "Contingency")
        assert_nil budget.area
        assert_equal [ person.record_id ], budget.own_owners.map(&:record_id)
      end

      # The compound path, clicked: the select is year- and centre-scoped while
      # area_id writes unscoped, so an area the picker does not offer read
      # "— none —" and an unrelated Save detached the budget.
      test "a Save that changes only the notes keeps an area from another year" do
        ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        next_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027")
        area = create_reimbursements_area(name: "Cogito", financial_year: next_year)
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        visit edit_admin_reimbursements_budget_path(budget.record_id)
        fill_in "Notes", with: "Checked with the committee"
        click_on "Save budget"

        assert_text "Budget saved"
        budget.reload
        assert_equal "Checked with the committee", budget.notes
        assert_equal area, budget.area
      end
    end
  end
end
