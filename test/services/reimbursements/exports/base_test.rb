require "test_helper"
require "caxlsx" # required lazily in app code

module Reimbursements
  module Exports
    ##
    # Base itself: one HEADERS + #row feeding both the CSV and the sheet, with
    # the formula guard applied on the way out of either.
    class BaseTest < ActiveSupport::TestCase
      # A minimal exporter over plain hashes, so no real resource's columns are involved.
      class Fake < Base
        HEADERS = [ "Name", "Amount", "When" ].freeze
        SHEET_NAME = "Fakes".freeze
        SLUG = "fakes".freeze

        private

        def row(record)
          [ record[:name], record[:amount], iso_date(record[:when]) ]
        end
      end

      setup do
        @exporter = Fake.new(store: nil)
        @records = [
          { name: "Fake blood", amount: BigDecimal("12.5"), when: Date.new(2026, 5, 13) },
          { name: "=HYPERLINK(\"http://evil\",\"click\")", amount: BigDecimal("-3.25"), when: nil }
        ]
      end

      test "to_csv writes headers and rows, quoting formulas and leaving blanks empty" do
        assert_equal [ [ "Name", "Amount", "When" ],
                       [ "Fake blood", "12.5", "2026-05-13" ],
                       [ "'=HYPERLINK(\"http://evil\",\"click\")", "-3.25", nil ] ],
                     CSV.parse(@exporter.to_csv(@records))
      end

      test "add_sheet builds a worksheet from the same headers and rows" do
        package = Axlsx::Package.new
        @exporter.add_sheet(package.workbook, @records)

        sheet = package.workbook.worksheets.first
        assert_equal "Fakes", sheet.name
        assert_equal [ "Name", "Amount", "When" ], sheet.rows.first.cells.map(&:value)
        assert_equal "Fake blood", sheet.rows[1].cells[0].value
        assert_equal 12.5, sheet.rows[1].cells[1].value
        assert_equal :float, sheet.rows[1].cells[1].type
        assert_equal "'=HYPERLINK(\"http://evil\",\"click\")", sheet.rows[2].cells[0].value
      end

      test "add_sheet keeps a numeric-looking identifier as literal text" do
        # 041000 must not arrive as 41000, nor "03" as 3.
        package = Axlsx::Package.new
        @exporter.add_sheet(package.workbook, [ { name: "041000", amount: 1, when: nil } ])

        cell = package.workbook.worksheets.first.rows[1].cells[0]
        assert_equal "041000", cell.value
        assert_equal :string, cell.type
      end

      # A nil checker reaching the first payee with bank details would be a NoMethodError.
      test "an exporter built without a checker still has a usable one" do
        assert_same ModulusCheck.default_checker, Fake.new(store: nil).send(:checker)
      end
    end
  end
end
