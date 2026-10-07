require "test_helper"
require "tmpdir"

module Reimbursements
  # A minimal synthetic rules table exercises the algorithm without the real files.
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

    test "a sort code with dashes normalizes like the same digits without them" do
      # Same pair as "known valid mod11".
      assert_equal ModulusCheck::VALID, checker([ BASIC_MOD11 ]).check("01-00-01", "00000030")
    end

    # Only dash and space are separators: a letter, tab or newline must fail, not be stripped.
    test "non-separators and bad lengths fail normalization" do
      [ [ "01-23-4X", "12345678" ], [ "01\t23\t45", "12345678" ], [ "01\n23\n45", "12345678" ],
        [ "12345", "12345678" ], [ "123456", "123" ] ].each do |sort_code, account|
        assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check(sort_code, account),
                     "#{sort_code.inspect} / #{account.inspect}"
      end
    end

    test "account with leading zeros is padded, not invalid" do
      refute_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("123456", "123456")
    end

    # --- Nine-digit ("nonstandard") account numbers (Pay.UK spec §2.1.2) ---

    test "a nine-digit account substitutes the sort code's last digit and validates" do
      # 019999 -> 019995 and account 90000000: total 187, 187 % 11 == 0.
      assert_equal ModulusCheck::VALID, checker([ BASIC_MOD11 ]).check("019999", "590000000")
    end

    test "a nine-digit account can still read invalid once substituted" do
      # Total 180, 180 % 11 == 4.
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
      # Without the substitution 010001 is outside the rule's range.
      assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ rule ]).check("010001", "12345678")

      # With it (010001 -> 020001) the math runs: total 98, 98 % 11 == 10.
      assert_equal ModulusCheck::INVALID,
                   checker([ rule ], { 10_001 => 20_001 }).check("010001", "12345678")
    end

    # --- Unsupported exceptions -------------------------------------------

    test "unsupported exceptions (9, and 14's roll numbers) return outside spec" do
      [ 9, 14 ].each do |exception|
        rule = BASIC_MOD11.with(exception: exception)
        assert_equal ModulusCheck::OUTSIDE_SPEC, checker([ rule ]).check("010001", "12345678"), "exception #{exception}"
      end
    end

    # --- File loading ------------------------------------------------------

    test "missing files yield an empty checker (outside spec)" do
      Dir.mktmpdir do |dir|
        c = ModulusCheck::Checker.from_files("#{dir}/nope.txt", "#{dir}/also-nope.txt")
        assert_equal ModulusCheck::OUTSIDE_SPEC, c.check("010001", "12345678")
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

    # --- Exception 5: Pay.UK spec vectors (spec §2.2.2.5) ------------------
    # Both checks must pass, each comparing a checkdigit: g (account[6]) with
    # 11 - remainder, then h (account[7]) with 10 - remainder.
    EX5_MOD11 = ModulusCheck::Rule.new(sort_from: 938_000, sort_to: 938_696, algorithm: "MOD11",
      weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 0, 0 ], exception: 5)
    EX5_DBLAL = ModulusCheck::Rule.new(sort_from: 938_000, sort_to: 938_696, algorithm: "DBLAL",
      weights: [ 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 0 ], exception: 5)

    def ex5_checker(substitutions = {})
      checker([ EX5_MOD11, EX5_DBLAL ], substitutions)
    end

    test "exception 5 matches the Pay.UK spec vectors" do
      {
        [ "938611", "07806039", {} ] => ModulusCheck::VALID, # case 14: both checks pass, no substitution
        [ "938063", "55065200", {} ] => ModulusCheck::VALID, # case 16: both remainders 0 (g=0, h=0)
        [ "938063", "15764273", {} ] => ModulusCheck::INVALID, # case 23: first digit right, second wrong
        [ "938063", "15764264", {} ] => ModulusCheck::INVALID, # case 24: first digit wrong, second right
        [ "938063", "15763217", {} ] => ModulusCheck::INVALID, # case 25: first check's remainder is 1
        [ "938600", "42368003", { 938_600 => 938_611 } ] => ModulusCheck::VALID # case 15: valid only after substitution
      }.each do |(sort_code, account, substitutions), expected|
        assert_equal expected, ex5_checker(substitutions).check(sort_code, account), "#{sort_code} / #{account}"
      end
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
      # Remainder 3 without the +27, 0 with it.
      assert_equal ModulusCheck::VALID, checker([ DBLAL_RULE ]).check("010001", "00000050")
      assert_equal ModulusCheck::INVALID, checker([ DBLAL_RULE.with(exception: 0) ]).check("010001", "00000050")
    end

    # --- Exception 3 (bypass when account digit c is 6 or 9) --------------

    test "exception 3 bypasses when account digit c (index 2) is 6 or 9" do
      rule = BASIC_MOD11.with(exception: 3)
      %w[00600001 00900001].each do |account|
        assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", account), account
      end
    end

    test "exception 3 runs the normal check when account digit c is neither 6 nor 9" do
      rule = BASIC_MOD11.with(exception: 3)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000030")
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "00000040")
    end

    # --- Exception 4 (remainder must equal the last two account digits) ---

    test "exception 4 passes only when the MOD11 remainder equals the account's last two digits" do
      # Remainder 8: "08" matches, "09" does not.
      rule = BASIC_MOD11.with(exception: 4)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000008")
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "00000009")
    end

    # --- Exception 7 -------------------------------------------------------

    test "exception 7 zeros all 8 weighting positions u-b, not just the sort-code 6" do
      # g is 9. Zeroing only positions 0-5 reads this vector VALID (the false
      # positive of #200/#201); zeroing 0-7 gives remainder 9.
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
      # a == g (both 5) but g != h (5 vs 1), so the real MOD11 runs: remainder 4.
      rule = BASIC_MOD11.with(exception: 6)
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "50000051")
    end

    # --- default_checker (vendored rule files) -----------------------------

    test "default_checker on real vendored files validates the Pay.UK spec vector" do
      # Canonical Pay.UK test vector #1: sort 08-99-99, account 66374958 -> valid.
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("089999", "66374958")
      # Exception 5 on the real files (spec cases 14, 15 and 23).
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("938611", "07806039")
      assert_equal ModulusCheck::VALID, ModulusCheck.default_checker.check("938600", "42368003")
      assert_equal ModulusCheck::INVALID, ModulusCheck.default_checker.check("938063", "15764273")
    end
  end
end
