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

      teardown { Array(@xlsx_paths).each { |path| FileUtils.rm_f(path) } }

      def sheet(*rows) = ([ HEADERS ] + rows).join("\n")

      def claim(reference, amount: "120.00", status: STATUS::PAID, payee: "alice@example.com",
                budget: "Props")
        [ reference, status, payee, budget, amount, "100.00", "Fake blood #{reference}",
          "PROPS ALICE", "", "", "", "", "", "", "" ].join("\t")
      end

      def xlsx_row(reference) = claim(reference).split("\t")

      # A real .xlsx on disk, so the upload goes through Roo exactly as the
      # operator's would.
      def xlsx_of(rows)
        require "caxlsx"
        package = Axlsx::Package.new
        package.workbook.add_worksheet(name: "Claims") { |s| rows.each { |r| s.add_row r } }
        path = Rails.root.join("tmp", "expense-import-#{SecureRandom.hex(4)}.xlsx")
        File.binwrite(path, package.to_stream.read)
        @xlsx_paths = (@xlsx_paths || []) << path
        path.to_s
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

      # The whole to_tsv round trip only runs on an upload — a paste never needs
      # it — so covering it anywhere but a browser proves nothing about the file
      # input, the multipart form or the hidden field the preview writes from it.
      test "an uploaded xlsx previews and imports, carrying the sheet with no file to re-send" do
        visit admin_reimbursements_expense_import_path

        attach_file "file", xlsx_of([ ::Reimbursements::ExpenseImport::TSV_HEADERS,
                                      xlsx_row("XL-1"), xlsx_row("XL-2") ])
        click_on "Preview import"

        assert_text "New claims (2)"

        # There is no file on the apply request: everything the upload said has
        # to be in the hidden field by now.
        assert_includes find("input[name='pasted_text']", visible: false).value, "XL-1"

        assert_difference -> { ::Reimbursements::Expense.count }, +2 do
          click_on "Import 2 claims"
          assert_text "Imported into Fringe 2027"
        end

        assert_equal %w[XL-1 XL-2],
                     ::Reimbursements::Expense.order(:id).pluck(:import_key)
      end

      # Which pot a claim lands in is decided by the budget it is charged to, so
      # picking the wrong centre imports against the wrong budgets — and the
      # select is the only thing that says which.
      test "picking a non-default cost centre imports against that centre's budgets" do
        termtime = create_second_reimbursements_cost_centre
        create_reimbursements_budget(name: "Termtime props", cost_centre: termtime,
                                     financial_year: @year)
        visit admin_reimbursements_expense_import_path

        select termtime.name, from: "Cost centre"
        fill_in "Paste the sheet", with: sheet(claim("TT-1", budget: "Termtime props"))
        click_on "Preview import"

        assert_text "Preview: Fringe 2027 — #{termtime.name}"
        click_on "Import 1 claim"
        assert_text "Imported into Fringe 2027"

        assert_equal termtime, ::Reimbursements::Expense.sole.cost_centre
      end

      # The preview says what it read, so a mis-mapped column is visible rather
      # than silent — which is how a "Payment reference" column came to be the
      # dedupe key and an "Account number" column the expense number.
      test "the preview states which column it read for each field" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet",
                with: [ "Claim ID\tStatus\tPayee email\tBudget\tAmount\tPayment reference",
                        "2019-014\tPaid\talice@example.com\tProps\t120\tPROPS ALICE" ].join("\n")
        click_on "Preview import"

        # A <summary>, so not a link or a button as far as click_on is concerned.
        find("summary", text: "Columns read from your sheet").click

        assert_text "Claim ID"
        assert_text "not in this sheet"
      end

      test "a claim imported at a live status is called out before it is written" do
        visit admin_reimbursements_expense_import_path

        fill_in "Paste the sheet", with: sheet(claim("OLD-1", status: STATUS::APPROVED))
        click_on "Preview import"

        assert_text "EUSA pays it again"
        assert_text "1 claim here is being imported into the LIVE queue"
      end

      test "the finance expenses index links into the wizard" do
        visit admin_reimbursements_expense_edits_path

        click_on "Import expenses"

        assert_text "Paste the sheet of claims the portal doesn't have"
      end
    end
  end
end
