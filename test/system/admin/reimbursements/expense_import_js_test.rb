require "application_system_test_case"
require_relative "../../../support/expense_import_sheet_helpers"

module Admin
  module Reimbursements
    ##
    # The expense import wizard, clicked for real. A request test POSTs straight to #preview
    # and #apply, so it cannot see the three things only a browser does:
    #
    #   * form_with must wrap the CardComponent: the footer is a slot, so a form opened
    #     inside renders its submit button outside the <form>;
    #   * the sheet survives into apply only through the preview's hidden field;
    #   * every step must render inside the Turbo Frame, or Turbo Drive discards the response.
    class ExpenseImportJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers
      include ExpenseImportSheetHelpers

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

      def sheet(*) = expense_import_sheet(*)

      # Sets the box the way a paste lands: fill_in TYPES the first four characters of a
      # long value as real keys, and the Tab in "ID\tStatus" leaves the textarea.
      def paste_sheet(with:)
        find_field("Paste the sheet").execute_script("this.value = arguments[0]", with)
      end

      def claim(reference, **cells)
        expense_import_row(reference: reference, description: "Fake blood #{reference}", **cells)
      end

      def xlsx_row(reference) = claim(reference).split("\t")

      # A real .xlsx on disk, so the upload goes through Roo.
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

        paste_sheet with: sheet(claim("OLD-1"), claim("OLD-2"))
        click_on "Preview import"

        assert_text "Preview: Fringe 2027"
        assert_text "New claims (2)"
        assert_text "Fake blood OLD-1"

        # The preview's hidden field is the only thing carrying the sheet into apply.
        assert_difference -> { ::Reimbursements::Expense.count }, +2 do
          click_on "Import 2 claims"
          assert_text "Imported into Fringe 2027"
        end
      end

      test "an unknown payee links to the screen that registers one" do
        visit admin_reimbursements_expense_import_path

        paste_sheet with: sheet(claim("OLD-1", payee_email: "nobody@example.com"))
        click_on "Preview import"

        assert_text "isn't anyone on the People screen"
        click_on "Register them on the People screen"

        assert_text "Register a person"
      end

      # The to_tsv round trip only runs on an upload, so only a browser exercises the file
      # input, the multipart form and the hidden field.
      test "an uploaded xlsx previews and imports, carrying the sheet with no file to re-send" do
        visit admin_reimbursements_expense_import_path

        attach_file "file", xlsx_of([ ::Reimbursements::ExpenseImport::TSV_HEADERS,
                                      xlsx_row("XL-1"), xlsx_row("XL-2") ])
        click_on "Preview import"

        assert_text "New claims (2)"

        # No file on the apply request: the hidden field has to carry everything.
        assert_includes find("input[name='pasted_text']", visible: false).value, "XL-1"

        assert_difference -> { ::Reimbursements::Expense.count }, +2 do
          click_on "Import 2 claims"
          assert_text "Imported into Fringe 2027"
        end

        assert_equal %w[XL-1 XL-2],
                     ::Reimbursements::Expense.order(:id).pluck(:import_key)
      end

      test "picking a non-default cost centre imports against that centre's budgets" do
        termtime = create_second_reimbursements_cost_centre
        create_reimbursements_budget(name: "Termtime props", cost_centre: termtime,
                                     financial_year: @year)
        visit admin_reimbursements_expense_import_path

        select termtime.name, from: "Cost centre"
        paste_sheet with: sheet(claim("TT-1", budget: "Termtime props"))
        click_on "Preview import"

        assert_text "Preview: Fringe 2027 · #{termtime.name}"
        click_on "Import 1 claim"
        assert_text "Imported into Fringe 2027"

        assert_equal termtime, ::Reimbursements::Expense.sole.cost_centre
      end
    end
  end
end
