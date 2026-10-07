require "test_helper"

module Reimbursements
  ##
  # The IBAN/BIC half of BankDetails. The UK helpers are exercised through the
  # forms and ModulusCheck.
  class BankDetailsTest < ActiveSupport::TestCase
    test "normalize_iban strips spaces, uppercases and is blank in, blank out" do
      assert_equal "DE89370400440532013000", BankDetails.normalize_iban("de89 3704 0044 0532 0130 00")
      assert_equal "GB29NWBK60161331926819", BankDetails.normalize_iban("GB29NWBK60161331926819")
      assert_equal "", BankDetails.normalize_iban(nil)
      assert_equal "", BankDetails.normalize_iban("  ")
    end

    # The mod-97 check catches the realistic error, a transposed or dropped
    # character; a shape check alone would let it through.
    test "valid_iban? accepts real IBANs from several countries" do
      # Documentation examples, never real accounts. FR has letters in the body.
      [
        "DE89 3704 0044 0532 0130 00",
        "GB29 NWBK 6016 1331 9268 19",
        "NL91 ABNA 0417 1643 00",
        "FR14 2004 1010 0505 0001 3M02 606",
        "de89370400440532013000"
      ].each do |iban|
        assert BankDetails.valid_iban?(iban), "expected #{iban} to be valid"
      end
    end

    test "valid_iban? rejects malformed values" do
      {
        "DE88 3704 0044 0532 0130 00" => "wrong check digits (DE89 -> DE88)",
        "DE89 3704 0044 0532 0130 09" => "a transposition inside the body",
        "DE89" => "too short",
        "DE89#{'1' * 40}" => "too long",
        "8022601234 5678" => "a UK sort code + account number",
        "1234 5678 9012 3456" => "no country prefix",
        "DEXX 3704 0044 0532 0130 00" => "letters where check digits go",
        # Only spaces are noise; anything else should be looked at, not cleaned.
        "DE89-3704-0044-0532-0130-00" => "punctuation is rejected rather than stripped",
        nil => "nil",
        "" => "blank"
      }.each do |value, reason|
        assert_not BankDetails.valid_iban?(value), "expected #{reason} to be invalid"
      end
    end

    test "format_iban groups in fours and leaves an unparseable value untouched" do
      assert_equal "DE89 3704 0044 0532 0130 00", BankDetails.format_iban("de89370400440532013000")
      assert_equal "not an iban", BankDetails.format_iban("not an iban")
    end

    test "mask_iban keeps the country and the last four characters" do
      assert_equal "DE****3000", BankDetails.mask_iban("DE89 3704 0044 0532 0130 00")
    end

    test "mask_iban takes the last four CHARACTERS, not the last four digits" do
      # Seychelles IBANs end in a currency code, so the digit-stripping .mask would mask the wrong end.
      assert_equal "SC****7USD", BankDetails.mask_iban("SC18 SSCB 1101 0000 0000 0000 1497 USD")
    end

    test "mask_iban is blank in, blank out" do
      assert_equal "", BankDetails.mask_iban(nil)
      assert_equal "", BankDetails.mask_iban("   ")
    end

    test "valid_bic? accepts 8 and 11 character codes, ignoring case and surrounding space" do
      [ "DEUTDEFF500", "NWBKGB2L", "  deutdeff500  " ].each do |bic|
        assert BankDetails.valid_bic?(bic), "expected #{bic.inspect} to be valid"
      end
      assert_equal "DEUTDEFF500", BankDetails.normalize_bic("  deutdeff500 ")
    end

    test "valid_bic? rejects other lengths, digits in the bank or country segments, and blank" do
      %w[DEUTDEFF5 DEUTDEFF50 NWBKGB2 DEU7DEFF500 DEUTD3FF500].push(nil, "").each do |bic|
        assert_not BankDetails.valid_bic?(bic), "expected #{bic.inspect} to be invalid"
      end
    end
  end
end
