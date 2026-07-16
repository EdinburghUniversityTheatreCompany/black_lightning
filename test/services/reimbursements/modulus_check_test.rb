require "test_helper"
require "tmpdir"

module Reimbursements
  # Ported from bedlam-bacs tests/test_modulus_check.py. Uses a minimal synthetic
  # rules table to exercise the Pay.UK modulus algorithm without the real files.
  class ModulusCheckTest < ActiveSupport::TestCase
    # Standard MOD11 weights: 7 6 5 4 3 2 7 6 5 4 3 2 1 0
    BASIC_MOD11 = ModulusCheck::Rule.new(
      sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
      weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0
    )

    def checker(rules, substitutions = {})
      ModulusCheck::Checker.new(rules, substitutions)
    end

    # --- Normalization -----------------------------------------------------

    test "sort code with dashes normalizes identically to the same digits without dashes" do
      dashed = checker([ BASIC_MOD11 ]).check("01-00-01", "00000030")
      undashed = checker([ BASIC_MOD11 ]).check("010001", "00000030")
      assert_equal undashed, dashed
      # Pin a concrete VALID outcome too — a broken dash-stripping regex would
      # leave the dashes in place, fail normalization, and short-circuit BOTH
      # sides to the *same* INVALID, which "still equal" alone wouldn't catch.
      # Asserting VALID specifically proves the digits genuinely reached (and
      # passed) the real modulus check, not just "both sides broke the same way."
      assert_equal ModulusCheck::VALID, dashed
    end

    test "a stray non-separator character fails normalization instead of being silently discarded" do
      # A letter isn't a documented separator (only dash/space are) — it must
      # make the sort code fail to normalize, not be dropped so the remaining
      # 6 digits coincidentally look clean and pass.
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("01-23-4X", "12345678")
    end

    test "a tab or newline is not a documented separator either, and must also fail normalization" do
      # \s (rather than a literal space) would also strip tabs/newlines --
      # a real risk for a value pasted from a spreadsheet cell -- silently
      # reducing to a clean-looking digit string that shouldn't pass.
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("01\t23\t45", "12345678")
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("01\n23\n45", "12345678")
    end

    test "short sort code returns invalid" do
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("12345", "12345678")
    end

    test "short account number returns invalid" do
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("123456", "123")
    end

    test "account with leading zeros is padded, not invalid" do
      refute_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("123456", "123456")
    end

    # --- Nine-digit ("nonstandard") account numbers (Pay.UK spec §2.1.2) ---
    # Rather than a hard INVALID, a 9-digit account substitutes the sort
    # code's last digit with the account number's own first digit, then
    # checks only the remaining 8 digits.

    test "a nine-digit account substitutes the sort code's last digit and validates" do
      # sort 019999 -> 019995 (last digit replaced by account[0]=5); account ->
      # 90000000 (the remaining 8 digits). Verified: total=187, 187 % 11 == 0.
      assert_equal ModulusCheck::VALID, checker([ BASIC_MOD11 ]).check("019999", "590000000")
    end

    test "a nine-digit account can still read invalid once substituted" do
      # Same sort substitution (account[0]=5 -> 019995), but a different
      # account digit: total=180, 180 % 11 == 4, not zero.
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("019999", "580000000")
    end

    test "a nine-digit account whose substituted sort code has no rule reads outside spec" do
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ BASIC_MOD11 ]).check("999999", "190000000")
    end

    # --- Sort-code range matching -----------------------------------------

    test "unknown sort code returns outside spec" do
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ BASIC_MOD11 ]).check("999999", "12345678")
    end

    # --- MOD11 algorithm ---------------------------------------------------

    test "known valid mod11" do
      # Sort 010001 -> 8; account 00000030 contributes 3; total 11, 11 % 11 == 0
      assert_equal ModulusCheck::VALID, checker([ BASIC_MOD11 ]).check("010001", "00000030")
    end

    test "known invalid mod11" do
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("010001", "00000040")
    end

    # --- Substitution table ------------------------------------------------

    test "substitution redirects sort code into a covered range and runs the real checkdigit math" do
      rule = ModulusCheck::Rule.new(sort_from: 20_000, sort_to: 29_999, algorithm: "MOD11",
        weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      # Without the substitution, 010001 isn't in this rule's 20000-29999
      # range at all -- proving the redirect actually happened, not just that
      # some rule happened to match.
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ rule ]).check("010001", "12345678")

      # With the substitution (010001 -> 020001), the checkdigit math actually
      # runs on the SUBSTITUTED code: total=98, 98 % 11 == 10, not zero.
      assert_equal ModulusCheck::INVALID,
                   checker([ rule ], { 10_001 => 20_001 }).check("010001", "12345678")
    end

    # --- Unsupported exceptions -------------------------------------------

    test "unsupported exception returns outside spec" do
      rule = BASIC_MOD11.with(exception: 9)
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ rule ]).check("010001", "12345678")
    end

    test "exception 14 returns outside spec" do
      rule = BASIC_MOD11.with(exception: 14)
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ rule ]).check("010001", "12345678")
    end

    # --- File loading ------------------------------------------------------

    test "missing files yield an empty checker (outside spec)" do
      Dir.mktmpdir do |dir|
        c = ModulusCheck::Checker.from_files("#{dir}/nope.txt", "#{dir}/also-nope.txt")
        assert_equal ModulusCheck::OUTSIDE_SPEC, c.check("010001", "12345678")
      end
    end

    test "parses a synthetic rules file" do
      Dir.mktmpdir do |dir|
        File.write("#{dir}/valacdos.txt", "010000 019999 MOD11 7 6 5 4 3 2 7 6 5 4 3 2 1 0\n")
        File.write("#{dir}/scsubtab.txt", "")
        c = ModulusCheck::Checker.from_files("#{dir}/valacdos.txt", "#{dir}/scsubtab.txt")
        assert_equal ModulusCheck::VALID, c.check("010001", "00000030")
      end
    end

    test "skips malformed and comment lines" do
      Dir.mktmpdir do |dir|
        File.write("#{dir}/valacdos.txt",
          "# comment\ngarbage line\n010000 019999 MOD11 7 6 5 4 3 2 7 6 5 4 3 2 1 0\n")
        File.write("#{dir}/scsubtab.txt", "")
        c = ModulusCheck::Checker.from_files("#{dir}/valacdos.txt", "#{dir}/scsubtab.txt")
        assert_equal ModulusCheck::VALID, c.check("010001", "00000030")
      end
    end

    test "leading-zero sort codes parse as base-10, not octal" do
      # Regression guard for the Integer(str, 10) fix. "018000" must parse as 18000,
      # so a rule covering 010000-019999 still applies.
      Dir.mktmpdir do |dir|
        File.write("#{dir}/valacdos.txt", "010000 019999 MOD11 7 6 5 4 3 2 7 6 5 4 3 2 1 0\n")
        File.write("#{dir}/scsubtab.txt", "")
        c = ModulusCheck::Checker.from_files("#{dir}/valacdos.txt", "#{dir}/scsubtab.txt")
        refute_equal ModulusCheck::OUTSIDE_SPEC, c.check("018000", "00000030")
      end
    end

    # --- Exception 5: Pay.UK spec vectors (VocaLink spec §2.2.2.5) ---------
    # Exception 5 is NOT "either check passes". Both the MOD11 first check and the
    # DBLAL second check must pass, and each uses a checkdigit comparison rather
    # than a plain zero remainder: the MOD11 check compares g (account[6]) against
    # 11-remainder, the DBLAL check compares h (account[7]) against 10-remainder.
    # The real 938000-938696 weights zero out the checkdigit positions.
    EX5_MOD11 = ModulusCheck::Rule.new(sort_from: 938_000, sort_to: 938_696, algorithm: "MOD11",
      weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 0, 0 ], exception: 5)
    EX5_DBLAL = ModulusCheck::Rule.new(sort_from: 938_000, sort_to: 938_696, algorithm: "DBLAL",
      weights: [ 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 0 ], exception: 5)

    def ex5_checker(substitutions = {})
      checker([ EX5_MOD11, EX5_DBLAL ], substitutions)
    end

    # Spec test case 14: both checks pass, no substitution.
    test "exception 5 spec vector: 938611 / 07806039 is valid" do
      assert_equal ModulusCheck::VALID, ex5_checker.check("938611", "07806039")
    end

    # Spec test case 16: both checks produce a remainder of 0 (g=0, h=0) and pass.
    test "exception 5 spec vector: 938063 / 55065200 is valid" do
      assert_equal ModulusCheck::VALID, ex5_checker.check("938063", "55065200")
    end

    # Spec test case 23: first checkdigit correct but second incorrect -> INVALID.
    # This is the case the old "either check passes" logic got WRONG (it would have
    # returned valid because the first check passes).
    test "exception 5 spec vector: 938063 / 15764273 is invalid (both checks required)" do
      assert_equal ModulusCheck::INVALID, ex5_checker.check("938063", "15764273")
    end

    # Spec test case 24: first checkdigit incorrect, second correct -> INVALID.
    test "exception 5 spec vector: 938063 / 15764264 is invalid" do
      assert_equal ModulusCheck::INVALID, ex5_checker.check("938063", "15764264")
    end

    # Spec test case 25: first check gives a remainder of 1 -> INVALID.
    test "exception 5 spec vector: 938063 / 15763217 is invalid (remainder 1)" do
      assert_equal ModulusCheck::INVALID, ex5_checker.check("938063", "15763217")
    end

    # Spec test case 15: valid only after sort-code substitution (938600 -> 938611).
    test "exception 5 spec vector: 938600 / 42368003 is valid with substitution" do
      assert_equal ModulusCheck::VALID, ex5_checker(938_600 => 938_611).check("938600", "42368003")
    end

    test "two rules without exception 5 still require both to pass" do
      rule1 = BASIC_MOD11
      rule2 = ModulusCheck::Rule.new(sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
        weights: [ 0, 0, 0, 0, 0, 0, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      assert_equal ModulusCheck::INVALID, checker([ rule1, rule2 ]).check("010001", "00000030")
    end

    # --- Exception 1 (DBLAL total += 27) -----------------------------------

    DBLAL_RULE = ModulusCheck::Rule.new(
      sort_from: 10_000, sort_to: 19_999, algorithm: "DBLAL",
      weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 1
    )

    test "exception 1 adds 27 to the DBLAL total before taking the remainder" do
      # Without +27 this account gives remainder 3 (would be invalid); the
      # +27 the exception adds brings it to remainder 0.
      assert_equal ModulusCheck::VALID, checker([ DBLAL_RULE ]).check("010001", "00000050")
    end

    test "exception 1 without the +27 would read invalid, proving the addition matters" do
      rule_no_exception = DBLAL_RULE.with(exception: 0)
      assert_equal ModulusCheck::INVALID, checker([ rule_no_exception ]).check("010001", "00000050")
    end

    # --- Exception 3 (bypass when account digit c is 6 or 9) --------------

    test "exception 3 bypasses when account digit c (index 2) is 6" do
      rule = BASIC_MOD11.with(exception: 3)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00600001")
    end

    test "exception 3 bypasses when account digit c (index 2) is 9" do
      rule = BASIC_MOD11.with(exception: 3)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00900001")
    end

    test "exception 3 runs the normal check when account digit c is neither 6 nor 9" do
      rule = BASIC_MOD11.with(exception: 3)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000030")
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "00000040")
    end

    # --- Exception 4 (remainder must equal the last two account digits) ---

    test "exception 4 passes when the MOD11 remainder equals the account's last two digits" do
      # remainder 8, last two digits "08" == 8.
      rule = BASIC_MOD11.with(exception: 4)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000008")
    end

    test "exception 4 fails when the remainder doesn't match the last two digits" do
      # remainder 8, last two digits "09" == 9 -- mismatch.
      rule = BASIC_MOD11.with(exception: 4)
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "00000009")
    end

    # --- Exception 7 -------------------------------------------------------

    test "exception 7 zeros all 8 weighting positions u-b, not just the sort-code 6" do
      # account digit g (index 6) is 9, triggering the zeroing. account_clean[0]
      # and [1] (weight positions 6/7 — the two account-side positions the old
      # bug left un-zeroed) are non-zero: with only positions 0-5 zeroed, this
      # vector's remainder is 0 (VALID) — the exact false positive #200/#201's
      # bug produced. Zeroing all 8 positions (0-7) correctly gives remainder 9.
      rule = BASIC_MOD11.with(exception: 7)
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "50000090")
    end

    test "exception 7 normal path when account digit g is not 9" do
      rule = BASIC_MOD11.with(exception: 7)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000030")
    end

    # --- Exception 6 ---------------------------------------------------------

    test "exception 6 bypasses as uncheckable when a is 4-8 and g==h (account[6]==account[7])" do
      # a=account[0]="5" (in 4-8); g=account[6]="9", h=account[7]="9" -> match.
      rule = BASIC_MOD11.with(exception: 6)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "50000099")
    end

    test "exception 6 does not bypass merely because account[0] coincidentally equals account[6]" do
      # The old bug's condition (account[0]==account[6]) is true here (both
      # "5"), but the spec's actual condition (g==h, i.e. account[6]==account[7])
      # is false ("5" vs "1") -- the real MOD11 math must run instead, giving
      # remainder 4 (INVALID), not a false-positive bypass to VALID.
      rule = BASIC_MOD11.with(exception: 6)
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "50000051")
    end

    # --- default_checker (vendored rule files) -----------------------------

    test "checker built from missing files reads OUTSIDE_SPEC, never raises" do
      absent = ModulusCheck::Checker.from_files("/no/such/valacdos.txt", "/no/such/scsubtab.txt")
      assert_equal ModulusCheck::OUTSIDE_SPEC, absent.check("089999", "66374958")
    end

    test "default_checker on real vendored files validates the Pay.UK spec vector" do
      valacdos = ModulusCheck::VALACDOS_PATH.call
      unless File.exist?(valacdos)
        skip "vendored Pay.UK rule files absent (#{valacdos}); see vendor/pay_uk/README.md"
      end

      ModulusCheck.reset_default_checker!
      # Canonical Pay.UK test vector #1: sort 08-99-99, account 66374958 -> valid.
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("089999", "66374958")
      # Exception 5 end-to-end on the real rule + substitution files (spec cases
      # 14, 15 and 23): both checks must pass, so 15764273 (first passes, second
      # fails) is invalid — the OR bug would have called it valid.
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("938611", "07806039")
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("938600", "42368003")
      assert_equal ModulusCheck::INVALID, ModulusCheck.default_checker.check("938063", "15764273")
    ensure
      ModulusCheck.reset_default_checker!
    end

    test "default_checker is memoized across calls" do
      ModulusCheck.reset_default_checker!
      assert_same ModulusCheck.default_checker, ModulusCheck.default_checker
    ensure
      ModulusCheck.reset_default_checker!
    end
  end
end
