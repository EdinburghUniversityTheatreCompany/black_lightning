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

    test "sort code with dashes is normalized before lookup (no raise)" do
      result = checker([ BASIC_MOD11 ]).check("01-23-45", "12345678")
      assert_includes [ ModulusCheck::VALID, ModulusCheck::INVALID, ModulusCheck::OUTSIDE_SPEC ], result
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

    test "nine digit account number returns invalid" do
      assert_equal ModulusCheck::INVALID, checker([ BASIC_MOD11 ]).check("010001", "123456789")
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

    test "substitution redirects sort code into a covered range" do
      rule = ModulusCheck::Rule.new(sort_from: 20_000, sort_to: 29_999, algorithm: "MOD11",
        weights: [ 7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      result = checker([ rule ], { 10_001 => 20_001 }).check("010001", "12345678")
      assert_includes [ ModulusCheck::VALID, ModulusCheck::INVALID ], result
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

    # --- Exception 5: two-rule OR logic -----------------------------------

    test "exception 5 valid when only the first rule passes" do
      rule1 = BASIC_MOD11.with(exception: 5)
      rule2 = ModulusCheck::Rule.new(sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
        weights: [ 0, 0, 0, 0, 0, 0, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      assert_equal ModulusCheck::VALID, checker([ rule1, rule2 ]).check("010001", "00000030")
    end

    test "exception 5 invalid when neither rule passes" do
      rule1 = BASIC_MOD11.with(exception: 5)
      rule2 = ModulusCheck::Rule.new(sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
        weights: [ 0, 0, 0, 0, 0, 0, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      assert_equal ModulusCheck::INVALID, checker([ rule1, rule2 ]).check("010001", "00000040")
    end

    test "exception 5 valid when only the second rule passes" do
      rule1 = BASIC_MOD11.with(exception: 5)
      rule2 = ModulusCheck::Rule.new(sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
        weights: [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ], exception: 0)
      assert_equal ModulusCheck::VALID, checker([ rule1, rule2 ]).check("010001", "00000040")
    end

    test "two rules without exception 5 still require both to pass" do
      rule1 = BASIC_MOD11
      rule2 = ModulusCheck::Rule.new(sort_from: 10_000, sort_to: 19_999, algorithm: "MOD11",
        weights: [ 0, 0, 0, 0, 0, 0, 7, 6, 5, 4, 3, 2, 1, 0 ], exception: 0)
      assert_equal ModulusCheck::INVALID, checker([ rule1, rule2 ]).check("010001", "00000030")
    end

    # --- Exception 7 -------------------------------------------------------

    test "exception 7 zeros sort-code weights when account digit g is 9" do
      rule = BASIC_MOD11.with(exception: 7)
      assert_equal ModulusCheck::INVALID, checker([ rule ]).check("010001", "00000090")
    end

    test "exception 7 normal path when account digit g is not 9" do
      rule = BASIC_MOD11.with(exception: 7)
      assert_equal ModulusCheck::VALID, checker([ rule ]).check("010001", "00000030")
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
