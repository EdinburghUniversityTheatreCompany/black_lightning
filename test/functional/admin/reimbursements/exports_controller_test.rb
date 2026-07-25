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
        get :show
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :show
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant access to the workbook" do
        submitter = users(:member_with_phone_number)
        grant_producer_permission(submitter)
        sign_in submitter

        get :show

        assert_response :forbidden
      end

      # --- The download ------------------------------------------------------

      test "answers an xlsx attachment named for today" do
        sign_in @user

        get :show

        assert_response :success
        assert_equal XLSX_TYPE, response.media_type
        disposition = response.headers["Content-Disposition"]
        assert_match(/attachment/, disposition)
        assert_match(/reimbursements-\d{4}-\d{2}-\d{2}\.xlsx/, disposition)
      end

      test "has one fixed-name sheet per resource" do
        sign_in @user

        get :show

        assert_equal [ "Expenses", "Actuals", "Budgets", "People", "Batches" ],
                     workbook.sheets
      end

      test "the Expenses sheet carries the exporter's headers and a known row" do
        sign_in @user

        get :show

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

        get :show

        rows = sheet_rows(workbook, "Budgets")
        assert_equal ::Reimbursements::Exports::Budgets::HEADERS, rows.first
        row = rows.find { |r| r[0] == "Props" }
        assert_equal "4000", row[1]
        assert_in_delta 1000.0, row[4], 0.001
        assert_equal "Pat Producer", row.last, "owners"
      end

      test "the Actuals and Batches sheets carry their rows" do
        sign_in @user

        get :show

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

        get :show

        rows = sheet_rows(workbook, "People")
        assert_equal ::Reimbursements::Exports::People::HEADERS, rows.first
        row = rows.find { |r| r[0] == "Pat Producer" }
        assert_equal "****9999", row[2], "sort code"
        assert_equal "****4958", row[3], "account number"
        assert_equal "Valid", row[4]
      end

      test "NO sheet of the workbook carries a full sort code or account number" do
        sign_in @user

        get :show

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
    end
  end
end
