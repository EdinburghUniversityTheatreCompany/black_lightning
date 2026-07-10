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

    test "raises when the template file is missing" do
      assert_raises(BacsXlsx::TemplateError) do
        BacsXlsx.new(template_path: Rails.root.join("lib/reimbursements/templates/nope.xlsx"))
      end
    end
  end
end
