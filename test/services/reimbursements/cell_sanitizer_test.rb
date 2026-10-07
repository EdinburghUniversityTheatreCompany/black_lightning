require "test_helper"

module Reimbursements
  class CellSanitizerTest < ActiveSupport::TestCase
    test "neutralises every leading formula trigger by prefixing a quote" do
      [ "=", "+", "-", "@", "\t", "\r", "\n" ].each do |trigger|
        assert_equal "'#{trigger}danger", CellSanitizer.sanitize("#{trigger}danger"),
                     "expected a leading #{trigger.inspect} to be neutralised"
      end
    end

    test "sanitize passes non-formula values through as text" do
      { "Fake blood" => "Fake blood", nil => "", "12.50" => "12.50",
        "2 + 2 props" => "2 + 2 props", 42 => "42" }.each do |input, out|
        assert_equal out, CellSanitizer.sanitize(input), input.inspect
      end
    end

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
