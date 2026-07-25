require "test_helper"

module Reimbursements
  # The one lenient money parser, shared by the submitter's ExpenseForm and the
  # finance budget forms. #parse answers nil for anything unreadable; #parse!
  # separates "nothing typed" (nil) from "typed something that isn't a number"
  # (raises), which is what lets a form tell a deliberate blank apart from a typo.
  class AmountParserTest < ActiveSupport::TestCase
    test "reads the formats people actually type" do
      assert_equal BigDecimal("1234.56"), AmountParser.parse("£1,234.56")
      assert_equal BigDecimal("1200"), AmountParser.parse("1,200")
      assert_equal BigDecimal("1200"), AmountParser.parse("£1200")
      assert_equal BigDecimal("12.5"), AmountParser.parse(" 12.50 ")
      assert_equal BigDecimal("42"), AmountParser.parse(42)
    end

    test "a trailing comma with one or two digits is a decimal comma, not thousands" do
      # Naively stripping the comma would record 1250 instead of 12.50.
      assert_equal BigDecimal("12.5"), AmountParser.parse("12,50")
      assert_equal BigDecimal("12.5"), AmountParser.parse("12,5")
      # With a decimal point present, commas are thousands separators.
      assert_equal BigDecimal("1200.50"), AmountParser.parse("1,200.50")
    end

    test "blank is nil from both entry points" do
      [ nil, "", "   ", "£" ].each do |blank|
        assert_nil AmountParser.parse(blank), blank.inspect
        assert_nil AmountParser.parse!(blank), blank.inspect
      end
    end

    test "parse! raises for a value that is present but not a number" do
      assert_raises(AmountParser::Error) { AmountParser.parse!("twelve pounds") }
      assert_raises(AmountParser::Error) { AmountParser.parse!("12ab") }
      assert_nil AmountParser.parse("twelve pounds")
    end
  end
end
