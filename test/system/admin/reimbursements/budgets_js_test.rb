require "application_system_test_case"

module Admin
  module Reimbursements
    # The budget form's area picker and owners list, clicked for real: a
    # request test cannot see what the browser fails to send.
    class BudgetsJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        login_as users(:member)
      end

      test "moves a budget to a different area, then detaches it, from its own form in the browser" do
        cogito = create_reimbursements_area(name: "Cogito")
        create_reimbursements_area(name: "Improverts")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: cogito)

        visit edit_admin_reimbursements_budget_path(budget.record_id)
        select "Improverts", from: "Area"
        click_on "Save budget"

        assert_text "Budget saved"
        assert_equal "Improverts", budget.reload.area.name

        # A fresh visit: the first save's flash would satisfy the next assert_text early.
        visit edit_admin_reimbursements_budget_path(budget.record_id)
        select "No area", from: "Area"
        click_on "Save budget"

        assert_text "Budget saved"
        assert_nil budget.reload.area
      end

      # A disabled fieldset submits none of its controls, so the browser sends
      # no owner_ids and the own rows stay untouched rather than synced to [].
      test "choosing an area on the new-budget form takes the owners list away" do
        create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        area = create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path
        tom_select_add "Alice Owner", from: "Owners"
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

      # A disabled fieldset stops the browser submitting its controls, but Tom
      # Select's control is divs and goes on looking live inside one.
      test "choosing an area visibly locks the owners widget" do
        create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path
        assert_no_selector ".ts-wrapper.disabled"

        select "Cogito", from: "Area"
        assert_selector ".ts-wrapper.disabled"

        select "No area", from: "Area"
        assert_no_selector ".ts-wrapper.disabled"
      end

      # Opened with ?area_id=, the widget is built after an async import(), so
      # without the select:ready handshake it is left looking live.
      test "a form opened with an area already chosen locks the widget too" do
        create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        area = create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path(area_id: area.record_id)

        assert_selector ".ts-wrapper.disabled"
      end

      # With no area the list is live, so the tests above cannot pass on a
      # fieldset that never enables.
      test "a line in no area still saves the owners ticked on the same form" do
        person = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        create_reimbursements_area(name: "Cogito")

        visit new_admin_reimbursements_budget_path
        tom_select_add "Alice Owner", from: "Owners"
        fill_in "Name", with: "Contingency"
        fill_in "Nominal code", with: "432340"
        click_on "Create budget"

        assert_text "Budget created"
        budget = ::Reimbursements::Budget.find_by!(name: "Contingency")
        assert_nil budget.area
        assert_equal [ person.record_id ], budget.own_owners.map(&:record_id)
      end

      # The Cost centre select narrows the areas, and drops a choice the new
      # centre does not hold rather than post it for the server to refuse.
      test "choosing a cost centre narrows the area picker to that centre's areas" do
        fringe = ::Reimbursements::CostCentre.default
        termtime = create_second_reimbursements_cost_centre
        create_reimbursements_area(name: "Fringe show", cost_centre: fringe)
        create_reimbursements_area(name: "Termtime show", cost_centre: termtime)
        create_reimbursements_area(name: "Unplaced show", cost_centre: nil)

        visit new_admin_reimbursements_budget_path
        select fringe.name, from: "Cost centre"
        assert_equal [ "No area", "Fringe show", "Unplaced show" ], area_option_names
        select "Fringe show", from: "Area"

        select termtime.name, from: "Cost centre"
        assert_equal [ "No area", "Termtime show", "Unplaced show" ], area_option_names
        assert_equal "", find_field("Area").value, "an area from the old centre must not stay chosen"

        select "Termtime show", from: "Area"
        fill_in "Name", with: "Marketing"
        fill_in "Nominal code", with: "432320"
        click_on "Create budget"

        assert_text "Budget created"
        budget = ::Reimbursements::Budget.find_by!(name: "Marketing")
        assert_equal [ "Termtime show", termtime ], [ budget.area.name, budget.cost_centre ]
      end

      # The picker is year- and centre-scoped while area_id writes unscoped, so
      # it must still offer the budget's own area.
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

      private

      def area_option_names
        find_field("Area").all("option").map(&:text)
      end
    end
  end
end
