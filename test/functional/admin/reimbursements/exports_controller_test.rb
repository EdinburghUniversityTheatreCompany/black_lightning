require "test_helper"
require "roo"

module Admin
  module Reimbursements
    ##
    # The combined workbook: one xlsx with a sheet per resource, served inline
    # from the Finance tooling. Parsed back with roo so the assertions are about
    # what finance actually opens, not about the builder's internals.
    class ExportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      MC = ::Reimbursements::ModulusCheck

      XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

      # The bank details seeded below, in the form they are stored. NONE of these
      # may appear anywhere in the workbook.
      RAW_SORT_CODE = "08-99-99".freeze
      RAW_ACCOUNT_NUMBER = "66374958".freeze

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: RAW_SORT_CODE,
                                               account_number: RAW_ACCOUNT_NUMBER)
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000",
                                               initial_budget: 1000, owners: [ @person ])
        @batch = create_reimbursements_batch(date_sent: Date.new(2026, 5, 13),
                                             draft_message_id: "msg-1")
        @expense = create_reimbursements_expense(
          person: @person, budget: @budget, batch: @batch, auto_number: 42,
          status: ::Reimbursements::Status::PAID, description: "Fake blood",
          amount: BigDecimal("12.5"), amount_excl_vat: BigDecimal("10.42"),
          payment_reference: "PROPS PAT", submitted_at: Time.utc(2026, 5, 1, 9)
        )
        create_reimbursements_actual(nominal_code: "439999", narrative: "Alice Producer",
                                     date: Date.new(2026, 5, 13), debit: BigDecimal("123.45"),
                                     period: "03", expense: @expense)

        @checker = FakeModulusChecker.new(RAW_ACCOUNT_NUMBER => MC::VALID)
        ExportsController.checker_builder = -> { @checker }
      end

      teardown do
        ExportsController.checker_builder = -> { MC.default_checker }
      end

      # The workbook as roo sees it, from the bytes the controller streamed.
      def workbook
        file = Tempfile.new([ "reimbursements-export", ".xlsx" ])
        file.binmode
        file.write(response.body)
        file.close
        Roo::Excelx.new(file.path)
      end

      def sheet_rows(book, name)
        book.sheet(name).to_a
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :download
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :download
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant access to the workbook" do
        submitter = users(:member_with_phone_number)
        grant_producer_permission(submitter)
        sign_in submitter

        get :download

        assert_response :forbidden
      end

      # --- The download ------------------------------------------------------

      test "answers an xlsx attachment named for today" do
        sign_in @user

        get :download

        assert_response :success
        assert_equal XLSX_TYPE, response.media_type
        disposition = response.headers["Content-Disposition"]
        assert_match(/attachment/, disposition)
        assert_match(/reimbursements-\d{4}-\d{2}-\d{2}\.xlsx/, disposition)
      end

      # The cover sheet comes FIRST: what a reader needs before any figure is
      # what the figures cover. Scope used to be mixed inside the file and
      # stated nowhere.
      test "has one fixed-name sheet per resource, behind a cover sheet" do
        sign_in @user

        get :download

        assert_equal [ "About this export", "Expenses", "Actuals", "Budgets", "Areas",
                       "Forecast revisions", "People", "Batches" ],
                     workbook.sheets
      end

      test "the Expenses sheet carries the exporter's headers and a known row" do
        sign_in @user

        get :download

        rows = sheet_rows(workbook, "Expenses")
        assert_equal ::Reimbursements::Exports::Expenses::HEADERS, rows.first
        row = rows.find { |r| r[0] == 42 }
        assert_equal "Paid", row[1]
        assert_equal "Pat Producer", row[2]
        assert_equal "Props", row[3]
        assert_in_delta 12.5, row[4], 0.001
        assert_equal "Fake blood", row[6]
      end

      test "the Budgets sheet carries the rollups" do
        sign_in @user

        get :download

        rows = sheet_rows(workbook, "Budgets")
        assert_equal ::Reimbursements::Exports::Budgets::HEADERS, rows.first
        row = rows.find { |r| r[0] == "Props" }
        assert_equal "4000", row[1]
        assert_in_delta 1000.0, row[4], 0.001
        assert_equal "Pat Producer", row[::Reimbursements::Exports::Budgets::HEADERS.index("Owners")],
                     "owners"
      end

      test "the Actuals and Batches sheets carry their rows" do
        sign_in @user

        get :download

        book = workbook
        actuals = sheet_rows(book, "Actuals")
        assert_equal ::Reimbursements::Exports::Actuals::HEADERS, actuals.first
        assert_equal "Alice Producer", actuals[1][2]
        assert_equal 42, actuals[1][5], "resolves the linked expense's auto-number"

        batches = sheet_rows(book, "Batches")
        assert_equal ::Reimbursements::Exports::Batches::HEADERS, batches.first
        assert_equal "2026-05-13", batches[1][0]
        assert_equal 1, batches[1][2], "one expense on the batch"
        assert_equal "Yes", batches[1][5]
      end

      # --- Masking ------------------------------------------------------------

      test "the People sheet MASKS both bank details to their last four digits" do
        sign_in @user

        get :download

        rows = sheet_rows(workbook, "People")
        assert_equal ::Reimbursements::Exports::People::HEADERS, rows.first
        row = rows.find { |r| r[0] == "Pat Producer" }
        assert_equal "****9999", row[2], "sort code"
        assert_equal "****4958", row[3], "account number"
        assert_equal "Valid", row[4]
      end

      test "NO sheet of the workbook carries a full sort code or account number" do
        sign_in @user

        get :download

        book = workbook
        book.sheets.each do |name|
          cells = sheet_rows(book, name).flatten.compact.map(&:to_s)
          assert_not_includes cells, RAW_ACCOUNT_NUMBER,
                              "the #{name} sheet leaked a full account number"
          assert_not_includes cells, RAW_SORT_CODE,
                              "the #{name} sheet leaked a full sort code"
          assert_not_includes cells, ::Reimbursements::BankDetails.normalize_sort_code(RAW_SORT_CODE),
                              "the #{name} sheet leaked an undashed sort code"
        end
      end

      # --- The page --------------------------------------------------------
      # This was a sidebar link that silently downloaded a file: no sheet list,
      # no scope, and no way to choose one.

      test "the page lists every sheet the workbook carries" do
        sign_in @user

        get :show

        assert_response :success
        ::Reimbursements::Exports::Workbook::SHEETS.each do |(exporter_class, _)|
          assert_match(/#{Regexp.escape(exporter_class::SHEET_NAME)}/, response.body,
                       "#{exporter_class::SHEET_NAME} is in the file but not on the page")
        end
      end

      test "the page describes every sheet rather than falling back" do
        sign_in @user

        get :show

        ::Reimbursements::Exports::Workbook::SHEETS.each do |(exporter_class, _)|
          key = "reimbursements.export_sheets.#{exporter_class::SLUG}"
          assert I18n.exists?(key), "#{exporter_class::SHEET_NAME} has no description"
        end
      end

      test "the page states how many rows each sheet would carry" do
        sign_in @user

        get :show

        assert_equal 1, assigns(:counts)["Expenses"]
        assert_equal 1, assigns(:counts)["Batches"]
      end

      test "the download link carries the page's own scope" do
        sign_in @user
        other = create_second_reimbursements_cost_centre

        get :show, params: { cost_centre: other.key }

        assert_select "a[href*=?]", "cost_centre=#{other.key}"
      end

      test "the page is finance-gated like the download" do
        sign_in users(:committee)

        get :show

        assert_response :forbidden
      end

      # --- The cover sheet and the two new sheets ----------------------------

      test "the cover sheet states the scope the file was pulled under" do
        sign_in @user
        other = create_second_reimbursements_cost_centre

        get :download, params: { cost_centre: other.key }

        cover = sheet_rows(workbook, "About this export").to_h { |k, v| [ k, v ] }
        assert_equal other.name, cover["Cost centre"]
        assert_equal Date.current.iso8601, cover["Exported"]
      end

      test "the cover sheet names every centre when none is selected" do
        sign_in @user

        get :download

        cover = sheet_rows(workbook, "About this export").to_h { |k, v| [ k, v ] }
        assert_equal "Every cost centre", cover["Cost centre"]
      end

      test "the Areas sheet carries a show's agreed total and owners" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ @person.id ])
        area.update!(initial_budget: BigDecimal("3000"))

        get :download

        rows = sheet_rows(workbook, "Areas")
        assert_equal ::Reimbursements::Exports::Areas::HEADERS, rows.first
        row = rows.find { |r| r.first == "Cogito" }
        assert row, "the area is missing from its own sheet"
        assert_equal 3000.0, row[1]
        assert_equal "Pat Producer", row[6]
      end

      # A plan of exactly £0 is a figure nobody filled in (PlannedAmount), and
      # a zero here would read as a show that agreed to spend nothing.
      test "an area with no agreed total exports an empty cell, not a zero" do
        sign_in @user
        create_reimbursements_area(name: "Unset")

        get :download

        row = sheet_rows(workbook, "Areas").find { |r| r.first == "Unset" }
        assert_nil row[1]
      end

      test "the Forecast revisions sheet carries each logged revision" do
        sign_in @user
        ::Reimbursements::DatabaseStore.new.create_forecast!(
          budget_id: @budget.record_id, amount: 950, date: Date.new(2026, 6, 1),
          reason: "June meeting"
        )

        get :download

        rows = sheet_rows(workbook, "Forecast revisions")
        assert_equal ::Reimbursements::Exports::Forecasts::HEADERS, rows.first
        row = rows.find { |r| r[3] == 950.0 }
        assert row, "the forecast is missing from its own sheet"
        assert_equal "Budget line", row[1]
        assert_equal "June meeting", row[4]
      end

      # A forecast belongs to exactly one of a budget or an area, so the sheet
      # says which rather than leaving a reader to infer it from a blank.
      test "an area's agreed-total revision is marked as one" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        ::Reimbursements::BudgetForecast.create!(area: area, amount: 4200,
                                                 date: Date.new(2026, 6, 1), reason: "Agreed")

        get :download

        row = sheet_rows(workbook, "Forecast revisions").find { |r| r[3] == 4200.0 }
        assert_equal "Area total", row[1]
        assert_equal "Cogito", row[2]
      end
    end
  end
end
