require "application_system_test_case"

module Admin
  module Reimbursements
    # The one browser-driven check on the areas admin screen: clicking the
    # real "Add budget line" / Save buttons. A request-level test POSTs
    # straight to the action and can't see a form_with opened INSIDE a
    # CardComponent (its submit renders outside the <form> and silently does
    # nothing) — only a system test clicking the real button catches that.
    class AreasJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        login_as users(:member)
      end

      test "adds a budget line to an area in the browser" do
        year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        centre = ::Reimbursements::CostCentre.default
        area = create_reimbursements_area(name: "Cogito", financial_year: year,
                                          cost_centre: centre)

        visit edit_admin_reimbursements_area_path(area.record_id)
        click_on "Add budget line"
        # stimulus-rails-nested-form's own wrapperSelector default — each row
        # (new or existing) is a ".nested-form-wrapper" div; the gem exposes
        # no "item" Stimulus target to select by.
        within all(".nested-form-wrapper").last do
          fill_in "Name", with: "Cogito: Marketing"
          fill_in "Nominal code", with: "432320"
        end
        click_on "Save"

        assert_text "Area saved"
        budget = area.reload.budgets.last
        assert_equal "Cogito: Marketing", budget&.name
        # The row posts only a name and a nominal code, so without inheriting
        # the area's coordinates the line lands unstamped — and the lenient
        # scoping then puts it in EVERY year's and EVERY centre's list, and in
        # every producer's budget picker in both centres.
        assert_equal year.id, budget.financial_year_id
        assert_equal centre.id, budget.cost_centre_id
      end

      # The basis is the one control on this form that changes a figure printed
      # beside it, and a request test POSTing straight to #update sees neither
      # the radio pair nor the card. Both live inside the same CardComponent
      # trap the test above exists for: a control whose submit renders outside
      # the <form> silently does nothing.
      test "switching an area to a net allowance changes the figure on its card" do
        area = create_reimbursements_area(name: "Committee", initial_budget: 1_000)
        create_reimbursements_budget(name: "Socials", nominal_code: "432320", area: area,
                                     initial_budget: 400)
        create_reimbursements_budget(name: "Raffle", nominal_code: "810000", area: area,
                                     budget_type: "Income", initial_budget: 800)

        visit edit_admin_reimbursements_area_path(area.record_id)

        within "dl" do
          # A spend cap: the £800 raised buys the committee no more room.
          assert_text "Total expenses"
          assert_text "£600.00"
        end

        choose "Total net"
        click_on "Save"

        assert_text "Area saved"
        assert_equal "net", area.reload.budget_basis
        within "dl" do
          # Netted: 1,000 - (400 - 800).
          assert_text "Total net"
          assert_text "£1,400.00"
          assert_no_text "Total expenses"
        end
      end

      test "a budget line saved with no nominal code is refused in the browser" do
        area = create_reimbursements_area(name: "Cogito")

        visit edit_admin_reimbursements_area_path(area.record_id)
        click_on "Add budget line"
        within all(".nested-form-wrapper").last do
          fill_in "Name", with: "Cogito: Marketing"
        end
        click_on "Save"

        assert_text "A new budget line needs a name and a nominal code"
        assert_empty area.reload.budgets
      end
    end
  end
end
