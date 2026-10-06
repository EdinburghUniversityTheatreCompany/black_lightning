require "test_helper"
require "roo"

module Admin
  module Reimbursements
    ##
    # The combined workbook, parsed back with roo so the assertions are about
    # what finance opens, not the builder's internals.
    class ExportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      MC = ::Reimbursements::ModulusCheck

      XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

      # The seeded bank details as stored. None may appear in any sheet.
      RAW_SORT_CODE = "08-99-99".freeze
      RAW_ACCOUNT_NUMBER = "66374958".freeze

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", sort_code: RAW_SORT_CODE,
                                               account_number: RAW_ACCOUNT_NUMBER)
        @budget = create_reimbursements_budget
        @batch = create_reimbursements_batch
        create_reimbursements_expense(person: @person, budget: @budget, batch: @batch)

        @checker = FakeModulusChecker.new(RAW_ACCOUNT_NUMBER => MC::VALID)
        ExportsController.checker_builder = -> { @checker }
      end

      teardown do
        ExportsController.checker_builder = -> { MC.default_checker }
      end

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

      test "requires sign-in" do
        get :download
        assert_redirected_to new_user_session_path
      end

      test "the producer portal permission alone does not grant access to the page or the workbook" do
        submitter = users(:member_with_phone_number)
        grant_producer_permission(submitter)
        sign_in submitter

        %i[show download].each do |action|
          get action
          assert_response :forbidden, action.to_s
        end
      end

      test "answers an xlsx attachment named for today" do
        sign_in @user

        get :download

        assert_response :success
        assert_equal XLSX_TYPE, response.media_type
        disposition = response.headers["Content-Disposition"]
        assert_match(/attachment/, disposition)
        assert_match(/reimbursements-\d{4}-\d{2}-\d{2}\.xlsx/, disposition)
      end

      # The cover sheet comes first: a reader needs the scope before any figure.
      test "has one fixed-name sheet per resource, behind a cover sheet, each with its exporter's headers" do
        sign_in @user

        get :download

        book = workbook
        assert_equal [ "About this export", "Expenses", "Actuals", "Budgets", "Areas",
                       "Forecast revisions", "People", "Batches" ],
                     book.sheets
        ::Reimbursements::Exports::Workbook::SHEETS.each do |exporter, _|
          assert_equal exporter::HEADERS, book.sheet(exporter::SHEET_NAME).row(1), exporter::SHEET_NAME
        end
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

      test "the page lists every sheet the workbook carries" do
        sign_in @user

        get :show

        assert_response :success
        ::Reimbursements::Exports::Workbook::SHEETS.each do |(exporter_class, _)|
          assert_match(/#{Regexp.escape(exporter_class::SHEET_NAME)}/, response.body,
                       "#{exporter_class::SHEET_NAME} is in the file but not on the page")
          assert I18n.exists?("reimbursements.export_sheets.#{exporter_class::SLUG}"),
                 "#{exporter_class::SHEET_NAME} has no description"
        end
      end

      test "the page states how many rows each sheet would carry" do
        sign_in @user

        get :show

        assert_equal 1, assigns(:counts)[::Reimbursements::Exports::Expenses]
        assert_equal 1, assigns(:counts)[::Reimbursements::Exports::Batches]
      end

      test "the download link carries the page's own scope" do
        sign_in @user
        other = create_second_reimbursements_cost_centre

        get :show, params: { cost_centre: other.key }

        assert_select "a[href*=?]", "cost_centre=#{other.key}"
      end

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

      # A £0 plan is unset (PlannedAmount); a zero here would read as an agreed spend of nothing.
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
