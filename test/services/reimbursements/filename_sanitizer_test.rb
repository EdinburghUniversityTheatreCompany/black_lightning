require "test_helper"

module Reimbursements
  class FilenameSanitizerTest < ActiveSupport::TestCase
    {
      "New XLR cables" => "New XLR cables",
      "file/name:with*bad?chars" => "file name with bad chars",
      "too    many    spaces" => "too many spaces",
      "  padded  " => "padded",
      "text\x00with\x1fnulls" => "text with nulls"
    }.each do |input, expected|
      test "sanitize_component turns #{input.inspect} into #{expected.inspect}" do
        assert_equal expected, FilenameSanitizer.sanitize_component(input)
      end
    end

    test "short descriptions unchanged" do
      assert_equal "Short text", FilenameSanitizer.truncate_description("Short text")
    end

    test "truncates at a word boundary" do
      text = "This is a fairly long description that needs to be truncated at some point"
      assert_equal "This is a fairly long", FilenameSanitizer.truncate_description(text, max_length: 30)
    end

    test "hard cut if no word break" do
      result = FilenameSanitizer.truncate_description("a" * 100, max_length: 30)
      assert_equal 30, result.length
    end

    {
      [ "New XLR cables", "IMG_1234.jpg", 1 ] => "2026-05-03 Tech - New XLR cables #417.jpg",
      [ "Cables", "receipt.PDF", 1 ] => "2026-05-03 Tech - Cables #417.pdf",
      [ "Cables", "img.jpg", 2 ] => "2026-05-03 Tech - Cables #417 (2).jpg",
      [ "Mic + DI: stage left/right", "r.jpg", 1 ] => "2026-05-03 Tech - Mic + DI stage left right #417.jpg",
      [ "Mystery file", "receipt_no_ext", 1 ] => "2026-05-03 Tech - Mystery file #417.bin"
    }.each do |(description, original, index), expected|
      test "build_receipt_filename gives #{expected}" do
        assert_equal expected, FilenameSanitizer.build_receipt_filename(
          bacs_date: Date.new(2026, 5, 3), budget_name: "Tech", description: description,
          auto_number: 417, original_filename: original, index: index
        )
      end
    end

    test "long description keeps the filename bounded and the claim number" do
      long_desc = "An incredibly verbose description that goes on and on " * 5
      result = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Tech",
        description: long_desc, auto_number: 417, original_filename: "r.jpg"
      )
      assert_operator result.length, :<, 200
      assert result.end_with?(" #417.jpg"), result
    end
  end
end
