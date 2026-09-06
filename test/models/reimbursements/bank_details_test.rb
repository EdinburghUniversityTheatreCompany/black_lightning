require "test_helper"

module Reimbursements
  ##
  # The international half of BankDetails. The UK sort-code/account-number
  # helpers are exercised through the forms and ModulusCheck; these are the
  # IBAN/BIC rules the international payment rail added, and they are pure
  # functions so they get pinned directly.
  class BankDetailsTest < ActiveSupport::TestCase
    # --- IBAN normalisation -------------------------------------------------

    test "normalize_iban strips spaces and uppercases" do
      assert_equal "DE89370400440532013000", BankDetails.normalize_iban("de89 3704 0044 0532 0130 00")
    end

    test "normalize_iban leaves an already-normalised value alone" do
      assert_equal "GB29NWBK60161331926819", BankDetails.normalize_iban("GB29NWBK60161331926819")
    end

    test "normalize_iban is blank in, blank out" do
      assert_equal "", BankDetails.normalize_iban(nil)
      assert_equal "", BankDetails.normalize_iban("  ")
    end

    # --- IBAN validation ----------------------------------------------------
    #
    # The mod-97 check is the whole point: it catches the realistic error, which
    # is a transposed or dropped character in a 22-34 character string nobody
    # reads back. A wrong IBAN that passes a shape check is money sent nowhere
    # recoverable.

    test "valid_iban? accepts real IBANs from several countries" do
      # Published documentation examples, never real accounts — the French one
      # carries letters inside the body, which the numeric conversion has to
      # handle.
      [
        "DE89 3704 0044 0532 0130 00",
        "GB29 NWBK 6016 1331 9268 19",
        "NL91 ABNA 0417 1643 00",
        "FR14 2004 1010 0505 0001 3M02 606"
      ].each do |iban|
        assert BankDetails.valid_iban?(iban), "expected #{iban} to be valid"
      end
    end

    test "valid_iban? accepts a lowercase, unspaced IBAN" do
      assert BankDetails.valid_iban?("de89370400440532013000")
    end

    test "valid_iban? rejects wrong check digits" do
      # DE89 -> DE88, the single-character error the check exists to catch.
      assert_not BankDetails.valid_iban?("DE88 3704 0044 0532 0130 00")
    end

    test "valid_iban? rejects a transposition inside the body" do
      assert_not BankDetails.valid_iban?("DE89 3704 0044 0532 0130 09")
    end

    test "valid_iban? rejects a value that is too short or too long" do
      assert_not BankDetails.valid_iban?("DE89")
      assert_not BankDetails.valid_iban?("DE89#{'1' * 40}")
    end

    test "valid_iban? rejects a value not shaped like an IBAN at all" do
      assert_not BankDetails.valid_iban?("8022601234 5678")  # a UK sort code + account number
      assert_not BankDetails.valid_iban?("1234 5678 9012 3456")  # no country prefix
      assert_not BankDetails.valid_iban?("DEXX 3704 0044 0532 0130 00")  # letters where check digits go
    end

    test "valid_iban? rejects punctuation rather than stripping it" do
      # Only spaces are noise a human adds; anything else means the value came
      # from somewhere unexpected and should be looked at, not silently cleaned.
      assert_not BankDetails.valid_iban?("DE89-3704-0044-0532-0130-00")
    end

    test "valid_iban? is false for blank" do
      assert_not BankDetails.valid_iban?(nil)
      assert_not BankDetails.valid_iban?("")
    end

    # --- IBAN display -------------------------------------------------------

    test "format_iban groups in fours" do
      assert_equal "DE89 3704 0044 0532 0130 00",
                   BankDetails.format_iban("de89370400440532013000")
    end

    test "format_iban leaves an unparseable value untouched" do
      assert_equal "not an iban", BankDetails.format_iban("not an iban")
    end

    test "mask_iban keeps the country and the last four characters" do
      # The country prefix is not identifying and tells an operator reading an
      # export which rail the payment took.
      assert_equal "DE****3000", BankDetails.mask_iban("DE89 3704 0044 0532 0130 00")
    end

    test "mask_iban takes the last four CHARACTERS, not the last four digits" do
      # Some countries' IBANs end in letters (Seychelles ends with a currency
      # code), so the digit-stripping BankDetails.mask would mask the wrong end.
      assert_equal "SC****7USD", BankDetails.mask_iban("SC18 SSCB 1101 0000 0000 0000 1497 USD")
    end

    test "mask_iban is blank in, blank out" do
      assert_equal "", BankDetails.mask_iban(nil)
      assert_equal "", BankDetails.mask_iban("   ")
    end

    # --- BIC / SWIFT --------------------------------------------------------

    test "valid_bic? accepts 8 and 11 character codes" do
      assert BankDetails.valid_bic?("DEUTDEFF500")   # 11, with a branch code
      assert BankDetails.valid_bic?("NWBKGB2L")      # 8
    end

    test "valid_bic? accepts lowercase and surrounding space" do
      assert BankDetails.valid_bic?("  deutdeff500  ")
    end

    test "valid_bic? rejects any other length" do
      assert_not BankDetails.valid_bic?("DEUTDEFF5")    # 9
      assert_not BankDetails.valid_bic?("DEUTDEFF50")   # 10
      assert_not BankDetails.valid_bic?("NWBKGB2")      # 7
    end

    test "valid_bic? rejects digits in the bank and country segments" do
      assert_not BankDetails.valid_bic?("DEU7DEFF500")  # digit in the bank code
      assert_not BankDetails.valid_bic?("DEUTD3FF500")  # digit in the country code
    end

    test "valid_bic? is false for blank" do
      assert_not BankDetails.valid_bic?(nil)
      assert_not BankDetails.valid_bic?("")
    end

    test "normalize_bic uppercases and strips space" do
      assert_equal "DEUTDEFF500", BankDetails.normalize_bic("  deutdeff500 ")
    end
  end
end
