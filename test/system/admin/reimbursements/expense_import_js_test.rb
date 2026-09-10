require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The expense import wizard, clicked for real.
    #
    # A request test cannot cover this: it POSTs straight to #preview and #apply
    # with whatever parameters it likes, so it passes just as happily when the
    # real form never sends them. Three things here are only visible to a
    # browser, and two of them have shipped broken in this app before:
    #
    #   * the form_with must wrap the CardComponent, not sit inside it — the
    #     footer is a component SLOT, so a form opened inside renders its submit
    #     button outside the <form> and the button silently does nothing;
    #   * the wizard is stateless, so the sheet only survives into apply through
    #     a hidden field the preview renders. A request test hands apply the
    #     text itself and proves nothing about that field;
    #   * every step must render inside the Turbo Frame, or Turbo Drive discards
    #     a perfectly good response and the screen never changes.
    class ExpenseImportJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      STATUS = ::Reimbursements::Status
      HEADERS = ::Reimbursements::ExpenseImport::TSV_HEADERS.join("\t").freeze

      setup do
        grant_finance_permission(users(:member))
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        @cost_centre = ::Reimbursements::CostCentre.default
        create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
        create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                     financial_year: @year)
        login_as users(:member)
      end

      def sheet(*rows) = ([ HEADERS ] + rows).join("\n")

      def claim(reference, amount: "120.00", status: STATUS::PAID, payee: "alice@example.com")
        [ reference, status, payee, "Props", amount, "100.00", "Fake blood #{reference}",
          "PROPS ALICE", "", "", "", "", "", "", "" ].join("\t")
      end

      test "pasting a sheet previews it and the confirm button imports it" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet", with: sheet(claim("OLD-1"), claim("OLD-2"))
        click_on "Preview import"

        # The preview reached the screen, which is what the Turbo Frame buys.
        assert_text "Preview: Fringe 2027"
        assert_text "New claims (2)"
        assert_text "Fake blood OLD-1"

        assert_difference -> { ::Reimbursements::Expense.count }, +2 do
          click_on "Import 2 claims"
          assert_text "Imported into Fringe 2027"
        end

        claim = ::Reimbursements::Expense.find_by(import_key: "OLD-1")
        assert_equal STATUS::PAID, claim.status
        assert_equal BigDecimal("120"), claim.amount
      end

      # The hidden field IS the wizard's state. Nothing else carries the sheet
      # from the preview into apply, so if it is missing the confirm button
      # imports an empty sheet and reports success over nothing.
      test "the preview carries the sheet in a hidden field, and apply reads it" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet", with: sheet(claim("OLD-1"))
        click_on "Preview import"

        carried = find("input[name='pasted_text']", visible: false).value
        assert_includes carried, "OLD-1"
        assert_includes carried, "Fake blood OLD-1"
      end

      test "a second import of the same sheet reports it and creates nothing" do
        visit admin_reimbursements_expense_import_path
        fill_in "Paste the sheet", with: sheet(claim("OLD-1"))
        click_on "Preview import"
        click_on "Import 1 claim"
        assert_text "Imported into Fringe 2027"

        visit admin_reimbursements_expense_import_path
        fill_in "Paste the sheet", with: sheet(claim("OLD-1"))
        click_on "Preview import"

        assert_text "has been imported before and will be skipped"
        # Nothing left to import, so the confirm button is not offered at all.
        assert_button "Nothing to import", disabled: true
        assert_equal 1, ::Reimbursements::Expense.count
      end

      test "an unreadable line blocks the whole sheet and names it" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet",
                with: sheet(claim("OLD-1"), claim("OLD-2", amount: "about a ton"))
        click_on "Preview import"

        assert_text "1 line can't be imported"
        assert_text "about a ton"
        assert_button "Import 1 claim", disabled: true
        assert_equal 0, ::Reimbursements::Expense.count
      end

      test "an unknown payee links to the screen that registers one" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet", with: sheet(claim("OLD-1", payee: "nobody@example.com"))
        click_on "Preview import"

        assert_text "isn't anyone on the People screen"
        click_on "Register them on the People screen"

        assert_text "Register a person"
      end

      test "the finance expenses index links into the wizard" do
        visit admin_reimbursements_expense_edits_path

        click_on "Import expenses"

        assert_text "Paste the sheet of claims that were settled outside the portal"
      end
    end
  end
end
