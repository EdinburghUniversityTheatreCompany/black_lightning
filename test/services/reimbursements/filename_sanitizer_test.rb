require "test_helper"

module Reimbursements
  # Ported from bedlam-bacs tests/test_filename_sanitizer.py. Builds the receipt
  # filenames EUSA sees: "<YYYY-MM-DD> <budget> - <description>[ (n)].<ext>".
  class FilenameSanitizerTest < ActiveSupport::TestCase
    # --- sanitize_component -----------------------------------------------

    test "passes safe text unchanged" do
      assert_equal "New XLR cables", FilenameSanitizer.sanitize_component("New XLR cables")
    end

    test "replaces forbidden chars with a space" do
      assert_equal "file name with bad chars",
        FilenameSanitizer.sanitize_component("file/name:with*bad?chars")
    end

    test "collapses runs of whitespace" do
      assert_equal "too many spaces", FilenameSanitizer.sanitize_component("too    many    spaces")
    end

    test "trims leading and trailing whitespace" do
      assert_equal "padded", FilenameSanitizer.sanitize_component("  padded  ")
    end

    test "strips control chars" do
      assert_equal "text with nulls", FilenameSanitizer.sanitize_component("text\x00with\x1fnulls")
    end

    # --- truncate_description ---------------------------------------------

    test "short descriptions unchanged" do
      assert_equal "Short text", FilenameSanitizer.truncate_description("Short text")
    end

    test "truncates at a word boundary" do
      text = "This is a fairly long description that needs to be truncated at some point"
      result = FilenameSanitizer.truncate_description(text, max_length: 30)
      refute result.end_with?("t") # not mid-word "truncat"
      assert_includes result, " "
      assert_operator result.length, :<=, 30
    end

    test "hard cut if no word break" do
      result = FilenameSanitizer.truncate_description("a" * 100, max_length: 30)
      assert_equal 30, result.length
    end

    # --- build_receipt_filename -------------------------------------------

    test "basic construction" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: "New XLR cables", original_filename: "IMG_1234.jpg"
      )
      assert_equal "2026-05-13 Tech - New XLR cables.jpg", result
    end

    test "pdf extension preserved and downcased" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Marketing",
        description: "Poster printing", original_filename: "receipt.PDF"
      )
      assert result.end_with?(".pdf")
    end

    test "second attachment has suffix" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: "Cables", original_filename: "img.jpg", index: 2
      )
      assert_equal "2026-05-13 Tech - Cables (2).jpg", result
    end

    test "unsafe characters in description are cleaned" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: "Mic + DI: stage left/right", original_filename: "r.jpg"
      )
      refute_includes result, "/"
      refute_includes result.sub(/\.jpg\z/, ""), ":"
    end

    test "no extension falls back to bin" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: "Mystery file", original_filename: "receipt_no_ext"
      )
      assert result.end_with?(".bin")
    end

    test "long description keeps the filename bounded" do
      long_desc = "An incredibly verbose description that goes on and on " * 5
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: long_desc, original_filename: "r.jpg"
      )
      assert_operator result.length, :<, 200
    end

    test "date format is iso" do
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 1, 5), budget_name: "FoH",
        description: "Bar restock", original_filename: "r.jpg"
      )
      assert result.start_with?("2026-01-05 ")
    end
  end
end
