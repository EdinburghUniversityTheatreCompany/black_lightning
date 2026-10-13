require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The budget import wizard, clicked for real. A request test POSTs
    # whatever parameters it likes; only a click proves the preview's hidden
    # fields (the sheet, the `canonical` marker, the ticks) reach apply.
    class BudgetImportJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        @cost_centre = ::Reimbursements::CostCentre.default
        login_as users(:member)
      end

      alias sheet budget_import_sheet

      def area_sheet(*rows)
        ([ "Area\tBudget name\tNominal code\tType\tBudget amount" ] + rows).join("\n")
      end

      def owner_sheet(*rows)
        ([ "Area\tBudget name\tNominal code\tType\tBudget amount\tOwner emails" ] + rows).join("\n")
      end

      # A budget name is the match key, so a rewritten backslash would be silent
      # corruption. The request test hands apply the marker itself.
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

      # The same file re-sent with owners filled in and no figures changed: the
      # button must not be disabled, and only a click touches the button.
      test "an owner-only sheet can actually be imported" do
        cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)
        create_reimbursements_budget(name: "Marketing", area: cogito, initial_budget: 400,
                                     cost_centre: @cost_centre, financial_year: @year)
        alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")

        visit admin_reimbursements_budget_import_path

        fill_in "Paste the sheet", with: owner_sheet(
          "Cogito\tMarketing\t432320\tExpense\t400\talice@example.com"
        )
        click_on "Preview import"

        assert_text "Who will sign off for each area after this import"
        assert_difference -> { ::Reimbursements::AreaOwner.count }, +1 do
          click_on "Import 1 area owner update"
          assert_text "Imported into Fringe 2027"
        end

        assert_equal [ alice.record_id ], cogito.reload.owner_ids
      end

      # A `name[]` checkbox array is where Rack's parsing has bitten this
      # wizard's siblings.
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
