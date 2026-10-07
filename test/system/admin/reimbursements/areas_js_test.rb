require "application_system_test_case"

module Admin
  module Reimbursements
    # Browser checks for the areas form: a request test POSTs straight to the
    # action and cannot see a form_with opened INSIDE a CardComponent, whose
    # submit renders outside the <form> and silently does nothing.
    class AreasJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        login_as users(:member)
      end

      test "adds a budget line to an area in the browser" do
        area = create_reimbursements_area(name: "Cogito")

        visit edit_admin_reimbursements_area_path(area.record_id)
        click_on "Add budget line"
        # Each nested row is a .nested-form-wrapper div (the gem's default
        # wrapperSelector); it exposes no target to select by.
        within all(".nested-form-wrapper").last do
          fill_in "Name", with: "Cogito: Marketing"
          fill_in "Nominal code", with: "432320"
        end
        click_on "Save"

        assert_text "Area saved"
        assert_equal "Cogito: Marketing", area.reload.budgets.last&.name
      end

      # The basis radios change a figure printed beside them, and a request test
      # sees neither the radios nor the card.
      test "switching an area to a net allowance changes the figure on its card" do
        area = create_reimbursements_area(name: "Committee", initial_budget: 1_000)
        create_reimbursements_budget(name: "Socials", nominal_code: "432320", area: area,
                                     initial_budget: 400)
        create_reimbursements_budget(name: "Raffle", nominal_code: "810000", area: area,
                                     budget_type: "Income", initial_budget: 800)

        visit edit_admin_reimbursements_area_path(area.record_id)

        within "dl" do
          # A spend cap: the £800 raised buys the committee no more room.
          assert_text "Agreed total (expenses)"
          assert_text "£600.00"
        end

        choose "Agreed total (net)"
        click_on "Save"

        assert_text "Area saved"
        assert_equal "net", area.reload.budget_basis
        within "dl" do
          # Netted: 1,000 - (400 - 800).
          assert_text "Agreed total (net)"
          assert_text "£1,400.00"
          assert_no_text "Agreed total (expenses)"
          # Printed as its two halves, not -£400, which reads as bad news (see
          # ReimbursementsHelper#reimbursements_area_allocation).
          assert_text "£400.00 of spend less £800.00 of income"
          assert_no_text "-£400.00"
        end
      end

      # A request test posts owner_ids directly; only a browser shows whether
      # the widget writes them back into the <select> the form actually submits.
      test "owners are chosen through the search widget and saved" do
        alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        bob = create_reimbursements_person(name: "Bob Owner", email: "bob@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ alice.id ])

        visit edit_admin_reimbursements_area_path(area.record_id)
        # The one already named renders as a chip rather than as an option.
        assert_selector ".ts-control .item", text: "Alice Owner"
        tom_select_add "Bob Owner", from: "Owners"
        click_on "Save"

        assert_text "Area saved"
        assert_equal [ alice, bob ].map(&:record_id).sort, area.reload.owner_ids.sort
      end

      # The other direction, and the one a bare `select_tag` gets wrong: with no
      # hidden empty field the post carries no owner_ids key and the area keeps
      # every owner it had.
      test "taking the last owner off the widget actually clears the owners" do
        alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ alice.id ])

        visit edit_admin_reimbursements_area_path(area.record_id)
        find(".ts-control .item", text: "Alice Owner").find(".remove").click
        click_on "Save"

        assert_text "Area saved"
        assert_empty area.reload.owner_ids
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
