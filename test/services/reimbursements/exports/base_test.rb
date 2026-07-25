require "test_helper"

module Reimbursements
  module Exports
    ##
    # The shared plumbing every exporter inherits: one HEADERS + #row definition
    # feeding both the CSV and the workbook sheet, with the formula-injection
    # guard applied on the way out of either.
    class BaseTest < ActiveSupport::TestCase
      # A minimal exporter over plain hashes, so this test covers Base itself
      # rather than any one resource's columns.
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

      test "to_csv writes the headers then one row per record" do
        rows = CSV.parse(@exporter.to_csv(@records))

        assert_equal [ "Name", "Amount", "When" ], rows.first
        assert_equal 3, rows.size, "header + two records"
        assert_equal [ "Fake blood", "12.5", "2026-05-13" ], rows[1]
      end

      test "to_csv neutralises a formula-injected cell" do
        rows = CSV.parse(@exporter.to_csv(@records))

        assert_equal "'=HYPERLINK(\"http://evil\",\"click\")", rows[2][0]
      end

      test "to_csv leaves a negative amount as a usable number, not quoted text" do
        rows = CSV.parse(@exporter.to_csv(@records))

        assert_equal "-3.25", rows[2][1], "a negative amount must not be quote-prefixed"
      end

      test "a blank date exports as an empty cell rather than a dash placeholder" do
        rows = CSV.parse(@exporter.to_csv(@records))

        assert_nil rows[2][2]
      end

      test "add_sheet builds a worksheet from the same headers and rows" do
        package = Axlsx::Package.new
        @exporter.add_sheet(package.workbook, @records)

        sheet = package.workbook.worksheets.first
        assert_equal "Fakes", sheet.name
        assert_equal [ "Name", "Amount", "When" ], sheet.rows.first.cells.map(&:value)
        assert_equal "Fake blood", sheet.rows[1].cells[0].value
        assert_equal 12.5, sheet.rows[1].cells[1].value
        assert_equal "'=HYPERLINK(\"http://evil\",\"click\")", sheet.rows[2].cells[0].value
      end

      test "add_sheet keeps a numeric-looking identifier as literal text" do
        # A nominal code or EUSA period must not be coerced to a number: 041000
        # would arrive as 41000 and "03" as 3.
        package = Axlsx::Package.new
        Fake.new(store: nil).add_sheet(package.workbook, [ { name: "041000", amount: 1, when: nil } ])

        cell = package.workbook.worksheets.first.rows[1].cells[0]
        assert_equal "041000", cell.value
        assert_equal :string, cell.type
      end

      test "add_sheet still types a real amount as a number" do
        package = Axlsx::Package.new
        Fake.new(store: nil).add_sheet(package.workbook, [ { name: "x", amount: BigDecimal("12.5"), when: nil } ])

        cell = package.workbook.worksheets.first.rows[1].cells[1]
        assert_equal 12.5, cell.value
        assert_equal :float, cell.type
      end

      test "add_sheet accepts an explicit sheet name" do
        package = Axlsx::Package.new
        @exporter.add_sheet(package.workbook, @records, name: "Something else")

        assert_equal "Something else", package.workbook.worksheets.first.name
      end

      test "the CSV filename carries the resource slug and the export date" do
        assert_equal "reimbursements-fakes-2026-05-13.csv",
                     @exporter.filename(date: Date.new(2026, 5, 13))
      end

      # People/Expenses read the checker for their bank-details verdict, and both
      # are built generically by Workbook, whose checker keyword defaults to nil
      # — a nil that reaches the first payee with bank details is a NoMethodError.
      test "an exporter built without a checker still has a usable one" do
        assert_same ModulusCheck.default_checker, Fake.new(store: nil).send(:checker)
      end

      test "an injected checker is never replaced by the default" do
        fake = Object.new
        assert_same fake, Fake.new(store: nil, checker: fake).send(:checker)
      end

      test "a subclass that forgets #row says so" do
        incomplete = Class.new(Base) { const_set(:HEADERS, [ "A" ]) }

        assert_raises(NotImplementedError) { incomplete.new(store: nil).to_csv([ {} ]) }
      end
    end
  end
end
