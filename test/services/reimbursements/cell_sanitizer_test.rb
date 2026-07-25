require "test_helper"

module Reimbursements
  class CellSanitizerTest < ActiveSupport::TestCase
    # --- sanitize (string in, string out) ----------------------------------

    test "neutralises every leading formula trigger by prefixing a quote" do
      [ "=", "+", "-", "@", "\t", "\r", "\n" ].each do |trigger|
        assert_equal "'#{trigger}danger", CellSanitizer.sanitize("#{trigger}danger"),
                     "expected a leading #{trigger.inspect} to be neutralised"
      end
    end

    test "leaves ordinary text untouched" do
      assert_equal "Fake blood", CellSanitizer.sanitize("Fake blood")
      assert_equal "", CellSanitizer.sanitize(nil)
      assert_equal "12.50", CellSanitizer.sanitize("12.50")
    end

    test "only the LEADING character matters, so mid-string operators survive" do
      assert_equal "2 + 2 props", CellSanitizer.sanitize("2 + 2 props")
    end

    test "coerces a non-string to its string form" do
      assert_equal "42", CellSanitizer.sanitize(42)
    end

    # --- cell (type-preserving, for mixed-type export rows) ----------------

    test "cell guards strings exactly as sanitize does" do
      assert_equal "'=HYPERLINK(\"http://evil\")", CellSanitizer.cell("=HYPERLINK(\"http://evil\")")
      assert_equal "Fake blood", CellSanitizer.cell("Fake blood")
    end

    test "cell passes non-strings through untouched so a negative amount stays a number" do
      assert_equal BigDecimal("-12.5"), CellSanitizer.cell(BigDecimal("-12.5"))
      assert_equal(-3, CellSanitizer.cell(-3))
      assert_nil CellSanitizer.cell(nil)
      assert_equal Date.new(2026, 5, 13), CellSanitizer.cell(Date.new(2026, 5, 13))
      assert CellSanitizer.cell(true)
    end
  end
end
