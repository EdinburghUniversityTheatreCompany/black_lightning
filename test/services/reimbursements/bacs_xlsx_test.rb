require "test_helper"

module Reimbursements
  class BacsXlsxTest < ActiveSupport::TestCase
    Row = BacsXlsx::BacsRow

    def rows
      [
        Row.new(payee_name: "Alice Producer", amount: 12.5, sort_code: "08-99-99",
                account_number: "00123456", nominal_code: "439999",
                description: "Fake blood", payment_reference: "PROPS ALICE", cost_centre: "F40"),
        Row.new(payee_name: "Bob Third Party", amount: 250.57, sort_code: "20-20-20",
                account_number: "50502366", nominal_code: "041000",
                description: "Van hire", payment_reference: "", cost_centre: "F40")
      ]
    end

    def parsed(bytes)
      RubyXL::Parser.parse_buffer(bytes)["BREAKDOWN"]
    end

    test "writes rows into the BREAKDOWN sheet from row 3 (0-based index 2)" do
      sheet = parsed(BacsXlsx.new.generate(rows))

      first = sheet.sheet_data[2]
      assert_equal "Alice Producer", first[0].value
      assert_in_delta 12.5, first[1].value, 0.001
      assert_equal "Fake blood", first[7].value
      assert_equal "PROPS ALICE", first[6].value

      second = sheet.sheet_data[3]
      assert_equal "Bob Third Party", second[0].value
    end

    test "forces text format on sort code, account number and nominal so leading zeros survive" do
      sheet = parsed(BacsXlsx.new.generate(rows))
      first = sheet.sheet_data[2]

      # Leading-zero values must round-trip as literal text, not as truncated numbers.
      assert_equal "00123456", first[3].value
      assert_equal "439999", first[4].value
      assert_equal "08-99-99", first[2].value

      assert_equal "@", first[2].number_format.format_code, "sort code must be text-formatted"
      assert_equal "@", first[3].number_format.format_code, "account number must be text-formatted"
      assert_equal "@", first[4].number_format.format_code, "nominal must be text-formatted"
    end

    test "leaves the header and example rows untouched" do
      sheet = parsed(BacsXlsx.new.generate(rows))

      assert_equal "PAYEE:", sheet.sheet_data[0][0].value
      assert_equal "E X AMPLE", sheet.sheet_data[1][0].value
    end

    test "an empty batch produces a valid template with no data rows" do
      sheet = parsed(BacsXlsx.new.generate([]))

      assert_nil sheet.sheet_data[2] && sheet.sheet_data[2][0]&.value
      assert_equal "PAYEE:", sheet.sheet_data[0][0].value
    end

    test "neutralises formula-injection in submitter text cells so Excel won't execute them" do
      malicious = Row.new(
        payee_name: "=HYPERLINK(\"http://evil\",\"click\")", amount: 5.0,
        sort_code: "08-99-99", account_number: "00123456", nominal_code: "439999",
        description: "@SUM(A1:A9)", payment_reference: "-2+3", cost_centre: "F40"
      )
      first = parsed(BacsXlsx.new.generate([ malicious ])).sheet_data[2]

      # A leading apostrophe forces the cell to literal text, so =, @, +, - values
      # can never be interpreted as a formula by Excel / on CSV export.
      assert_equal "'=HYPERLINK(\"http://evil\",\"click\")", first[0].value
      assert_equal "'@SUM(A1:A9)", first[7].value
      assert_equal "'-2+3", first[6].value
    end

    test "leaves ordinary text cells and forced-text bank fields unprefixed" do
      first = parsed(BacsXlsx.new.generate(rows)).sheet_data[2]

      assert_equal "Alice Producer", first[0].value
      assert_equal "Fake blood", first[7].value
      assert_equal "PROPS ALICE", first[6].value
      # Forced-text bank fields keep their leading zeros/dashes and are never prefixed.
      assert_equal "08-99-99", first[2].value
      assert_equal "00123456", first[3].value
      assert_equal "439999", first[4].value
    end

    test "a negative amount stays a numeric cell, never quote-prefixed" do
      refund = Row.new(payee_name: "Refund Payee", amount: -12.5, sort_code: "08-99-99",
                       account_number: "00123456", nominal_code: "439999",
                       description: "Refund", payment_reference: "REF", cost_centre: "F40")
      cell = parsed(BacsXlsx.new.generate([ refund ])).sheet_data[2][1]

      assert_in_delta(-12.5, cell.value, 0.001)
    end

    test "raises when the template file is missing" do
      assert_raises(BacsXlsx::TemplateError) do
        BacsXlsx.new(template_path: Rails.root.join("lib/reimbursements/templates/nope.xlsx"))
      end
    end

    def full_batch(count)
      (1..count).map do |n|
        Row.new(payee_name: "Payee #{n}", amount: n.to_f, sort_code: "20-20-20",
               account_number: "50502366", nominal_code: "439999",
               description: "Expense #{n}", payment_reference: "REF#{n}", cost_centre: "F40")
      end
    end

    test "a full 200-row batch fills every data row and the GRAND TOTAL formula covers all of them" do
      workbook = RubyXL::Parser.parse_buffer(BacsXlsx.new.generate(full_batch(BacsXlsx::MAX_ROWS)))
      sheet = workbook["BREAKDOWN"]

      first_row = sheet.sheet_data[2]
      last_row = sheet.sheet_data[2 + BacsXlsx::MAX_ROWS - 1]
      assert_equal "Payee 1", first_row[0].value
      assert_equal "Payee 200", last_row[0].value

      total_row = sheet.sheet_data[2 + BacsXlsx::MAX_ROWS]
      assert_equal "GRAND TOTAL", total_row[0].value
      assert_equal "SUM(B3:B202)", total_row[1].formula.expression

      written_sum = (2...(2 + BacsXlsx::MAX_ROWS)).sum { |r| sheet.sheet_data[r][1].value }
      assert_in_delta (1..200).sum, written_sum, 0.001, "every row must fall inside the summed range"

      auth_total = workbook["AUTHORISATION FORM"].sheet_data[10][2]
      assert_equal "SUM(BREAKDOWN!B3:B202)", auth_total.formula.expression
    end

    test "refuses a batch bigger than the template's row capacity instead of corrupting the total" do
      error = assert_raises(BacsXlsx::TemplateError) { BacsXlsx.new.generate(full_batch(BacsXlsx::MAX_ROWS + 1)) }

      assert_match(/201 expenses exceed/, error.message)
    end
  end
end
