require "test_helper"
require "bigdecimal"

module Reimbursements
  # Ported from bedlam-bacs tests/test_reconciliation.py (parse + dedup half;
  # the match_* fns port alongside the extended Expense/Budget POROs).
  class ReconciliationTest < ActiveSupport::TestCase
    # The pure Reconciliation matchers read the AR models' public interface
    # (effective nominal code, amounts, dates); built unpersisted.
    Expense = Reimbursements::Expense
    Budget = Reimbursements::Budget

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze
    SAMPLE_ROW = "439999\tF40\tBACS001\t15/03/2025\t03\tAlice Producer\tSome show\t123.45\t\t123.45".freeze
    SAMPLE_CSV_ROW = "439999,F40,BACS001,15/03/2025,03,Alice Producer,Some show,123.45,,123.45".freeze

    def bd(value)
      BigDecimal(value.to_s)
    end

    # --- actuals_row_dedup_key --------------------------------------------

    test "zero decimal matches an absent (nil) field" do
      assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", nil, nil)
    end

    test "negative zero matches an ordinary (positive) zero" do
      assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd("-0.00"), bd("-0.00"))
    end

    test "zero decimal matches an empty-string field" do
      assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd("123.45")),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", "", 123.45)
    end

    test "non-zero decimal matches the same value stored as a float" do
      assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd("123.45"), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", 123.45, nil)
    end

    test "narrative whitespace is stripped in the key" do
      assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "  Alice Producer  ", bd(0), bd(0))
    end

    test "different amounts do not match" do
      refute_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd("100.00"), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd("200.00"), bd(0))
    end

    test "different nominal codes do not match" do
      refute_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd(0)),
        Reconciliation.actuals_row_dedup_key("250000", "Alice Producer", bd(0), bd(0))
    end

    test "different narratives do not match" do
      refute_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd(0), bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Bob Producer", bd(0), bd(0))
    end

    test "dedup key preserves amounts beyond float precision" do
      # Two amounts a penny apart both collapse to the same Float, so a
      # float-normalised key would wrongly treat them as the same imported row
      # (and silently skip the second). A BigDecimal key keeps them distinct.
      big = BigDecimal("9999999999999999.99")
      penny_less = BigDecimal("9999999999999999.98")
      refute_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", big, bd(0)),
        Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", penny_less, bd(0))
    end

    test "dedup key is four strings" do
      key = Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", bd("123.45"), nil)
      assert_equal 4, key.length
      assert(key.all? { |part| part.is_a?(String) })
    end

    # --- parse_actuals_rows: legacy format --------------------------------

    test "empty string returns empty list" do
      assert_empty Reconciliation.parse_actuals_rows("")
    end

    test "whitespace-only returns empty list" do
      assert_empty Reconciliation.parse_actuals_rows("   \n  \t  ")
    end

    test "tab-separated single row" do
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}")
      assert_equal 1, rows.length
      row = rows.first
      assert_equal "439999", row.nominal_code
      assert_equal "F40", row.cost_centre
      assert_equal "BACS001", row.ref
      assert_equal Date.new(2025, 3, 15), row.date
      assert_equal "03", row.period
      assert_equal "Alice Producer", row.narrative
      assert_equal "Some show", row.narrative_1
      assert_equal bd("123.45"), row.debit
      assert_equal bd(0), row.credit
      assert_equal bd("123.45"), row.net
    end

    test "comma-separated single row" do
      header = "Nominal,Cost Centre,Ref,Date,Period,Narrative,Narrative 1,Debit,Credit,Net"
      rows = Reconciliation.parse_actuals_rows("#{header}\n#{SAMPLE_CSV_ROW}")
      assert_equal 1, rows.length
      assert_equal "439999", rows.first.nominal_code
      assert_equal bd("123.45"), rows.first.debit
    end

    test "skips blank lines" do
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}\n\n#{SAMPLE_ROW}")
      assert_equal 2, rows.length
    end

    test "british date parsing" do
      row_text = "439999\tF40\tBACS001\t01/12/2024\t12\tNarr\tNarr1\t50.00\t\t50.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}")
      assert_equal Date.new(2024, 12, 1), rows.first.date
    end

    test "credit row" do
      row_text = "250000\tF40\tINC001\t10/04/2025\t04\tGrant income\t\t\t1000.00\t-1000.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}")
      assert_equal bd("1000.00"), rows.first.credit
      assert_equal bd(0), rows.first.debit
      assert_equal bd("-1000.00"), rows.first.net
    end

    test "raises on too few columns" do
      error = assert_raises(ArgumentError) do
        Reconciliation.parse_actuals_rows("#{HEADER}\n439999\tF40\tBACS001")
      end
      assert_match(/columns/, error.message)
    end

    test "raises when the header is missing a required column" do
      header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      error = assert_raises(ArgumentError) do
        Reconciliation.parse_actuals_rows("#{header}\n439999\tF40\tBACS001\t01/12/2024\tNarr\tNarr1\t50.00\t\t50.00")
      end
      assert_match(/missing required columns/i, error.message)
      assert_match(/period/i, error.message)
    end

    test "raises when the header has no amount columns at all (no GoodsValue, no Debit/Credit/Net)" do
      header = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative"
      error = assert_raises(ArgumentError) do
        Reconciliation.parse_actuals_rows("#{header}\n439999\tF40\tBACS001\t01/12/2024\t12\tNarr")
      end
      assert_match(/GoodsValue column or Debit.Credit.Net/i, error.message)
    end

    test "parses an ISO 8601 date when the DD/MM/YYYY parse doesn't apply" do
      row_text = "439999\tF40\tBACS001\t2024-12-01\t12\tNarr\tNarr1\t50.00\t\t50.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}")
      assert_equal Date.new(2024, 12, 1), rows.first.date
    end

    test "a DD/MM/YY (2-digit year) date raises rather than silently landing in year 89" do
      row_text = "439999\tF40\tBACS001\t15/03/89\t12\tNarr\tNarr1\t50.00\t\t50.00"
      error = assert_raises(ArgumentError) { Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}") }
      assert_match(/Cannot parse date/, error.message)
    end

    test "raises a clear error for a genuinely unparseable date" do
      row_text = "439999\tF40\tBACS001\tnot-a-date\t12\tNarr\tNarr1\t50.00\t\t50.00"
      error = assert_raises(ArgumentError) { Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}") }
      assert_match(/Cannot parse date/, error.message)
    end

    test "multiple rows parsed correctly" do
      row2 = "250000\tF40\tINC001\t20/03/2025\t03\tGrant\t\t\t500.00\t-500.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}\n#{row2}")
      assert_equal 2, rows.length
      assert_equal "439999", rows[0].nominal_code
      assert_equal "250000", rows[1].nominal_code
    end

    test "amounts with commas are parsed" do
      row_text = "439999\tF40\tBACS001\t15/03/2025\t03\tNarr\tNarr1\t1,234.56\t\t1,234.56"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}")
      assert_equal bd("1234.56"), rows.first.debit
    end

    test "non-F40 cost centre rows are excluded" do
      other = "439999\tF99\tBACS001\t15/03/2025\t03\tAlice\tShow\t123.45\t\t123.45"
      assert_empty Reconciliation.parse_actuals_rows("#{HEADER}\n#{other}")
    end

    test "F40 cost centre row is included" do
      assert_equal 1, Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}").length
    end

    test "empty cost centre row is included" do
      row_text = "439999\t\tBACS001\t15/03/2025\t03\tAlice\tShow\t123.45\t\t123.45"
      assert_equal 1, Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}").length
    end

    test "mixed cost centres filter correctly" do
      other = "439999\tF99\tBACS002\t15/03/2025\t03\tBob\tOther\t50.00\t\t50.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}\n#{other}")
      assert_equal 1, rows.length
      assert_equal "F40", rows.first.cost_centre
    end

    test "cost_centre_code argument selects a different cost centre" do
      # Per-cost-centre readiness: a BED row is kept when we ask for BED, not F40.
      bed = "439999\tBED\tBACS001\t15/03/2025\t03\tAlice\tShow\t10.00\t\t10.00"
      text = "#{HEADER}\n#{SAMPLE_ROW}\n#{bed}"
      assert_equal [ "F40" ], Reconciliation.parse_actuals_rows(text).map(&:cost_centre)
      assert_equal [ "BED" ], Reconciliation.parse_actuals_rows(text, cost_centre_code: "BED").map(&:cost_centre)
    end

    # --- parse_actuals_rows: Sage export format ---------------------------

    SAGE_HEADER = [
      "NLNominalAccounts.AccountNumber", "NLNominalAccounts.AccountCostCentre",
      "NLNominalAccounts.AccountDepartment", "NLNominalAccounts.AccountName",
      "NLPostedNominalTrans.TransactionDate", "SYSAccountingPeriods.PeriodNumber",
      "NLPostedNominalTrans.Reference", "NLPostedNominalTrans.Narrative",
      "NLPostedNominalTrans.GoodsValueInBaseCurrency", "SYSCompanies.CompanyName"
    ].join("\t").freeze
    SAGE_DEBIT_ROW = "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t24/04/2026\t1\tBACS\tEN-LIANG LEE - TECH PC GRAPHICS CARD\t118.24\tEUSA".freeze
    SAGE_CREDIT_ROW = "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t26/04/2026\t1\t0000001431\tSI / EUSAC201 / 0000001431\t-400.56\tEUSA".freeze

    test "sage debit row" do
      row = Reconciliation.parse_actuals_rows("#{SAGE_HEADER}\n#{SAGE_DEBIT_ROW}").first
      assert_equal bd("118.24"), row.debit
      assert_equal bd(0), row.credit
      assert_equal bd("118.24"), row.net
    end

    test "sage credit row" do
      row = Reconciliation.parse_actuals_rows("#{SAGE_HEADER}\n#{SAGE_CREDIT_ROW}").first
      assert_equal bd(0), row.debit
      assert_equal bd("400.56"), row.credit
      assert_equal bd("-400.56"), row.net
    end

    test "sage field mapping" do
      row = Reconciliation.parse_actuals_rows("#{SAGE_HEADER}\n#{SAGE_DEBIT_ROW}").first
      assert_equal "431580", row.nominal_code
      assert_equal "F40", row.cost_centre
      assert_equal "BACS", row.ref
      assert_equal Date.new(2026, 4, 24), row.date
      assert_equal "1", row.period
      assert_equal "EN-LIANG LEE - TECH PC GRAPHICS CARD", row.narrative
      assert_equal "", row.narrative_1
    end

    test "legacy format still works alongside sage support" do
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}")
      assert_equal 1, rows.length
      assert_equal "439999", rows.first.nominal_code
      assert_equal bd("123.45"), rows.first.debit
    end

    test "sage real data sample" do
      sample = [
        SAGE_HEADER,
        "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t24/04/2026\t1\tBACS\tEN-LIANG LEE - TECH PC GRAPHICS CARD\t118.24\tEUSA",
        "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t24/04/2026\t1\tBACS\tEN-LIANG LEE - TECH PC MOTHERBOARD\t85.38\tEUSA",
        "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t26/04/2026\t1\t0000001431\tSI / EUSAC201 / 0000001431\t-400.56\tEUSA"
      ].join("\n")
      rows = Reconciliation.parse_actuals_rows(sample)
      assert_equal 3, rows.length
      assert_equal bd("118.24"), rows[0].debit
      assert_equal bd("85.38"), rows[1].debit
      assert_equal bd("400.56"), rows[2].credit
      assert_equal bd("-400.56"), rows[2].net
    end

    # --- match_debit_to_expense -------------------------------------------

    def debit_row(nominal_code: "439999", debit: bd("123.45"), row_date: Date.new(2025, 3, 15))
      Reconciliation::ActualsRow.new(
        nominal_code: nominal_code, cost_centre: "F40", ref: "BACS001", date: row_date,
        period: "03", narrative: "Test", narrative_1: "", debit: debit, credit: bd(0), net: debit
      )
    end

    def expense(nominal_code: "439999", amount: bd("123.45"), amount_excl_vat: nil,
                submitted_date: Date.new(2025, 3, 15), payment_confirmed_date: nil)
      Expense.new(
        auto_number: 1, status: Status::SUBMITTED,
        amount: amount, amount_excl_vat: amount_excl_vat,
        budget: Budget.new(name: "Production", nominal_code: nominal_code),
        submitted_to_eusa_date: submitted_date, payment_confirmed_date: payment_confirmed_date
      )
    end

    test "debit exact match" do
      exp = expense
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row, [ exp ])
    end

    test "debit no match on wrong nominal" do
      assert_nil Reconciliation.match_debit_to_expense(debit_row(nominal_code: "999999"), [ expense ])
    end

    test "debit no match when amount too different" do
      assert_nil Reconciliation.match_debit_to_expense(debit_row(debit: bd("200.00")),
        [ expense(amount: bd("123.45")) ])
    end

    test "debit matches within a penny" do
      exp = expense(amount: bd("123.44"))
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(debit: bd("123.45")), [ exp ])
    end

    test "debit no match just over a penny" do
      assert_nil Reconciliation.match_debit_to_expense(debit_row(debit: bd("123.45")),
        [ expense(amount: bd("123.43")) ])
    end

    test "debit matches when date within 14 days" do
      exp = expense(submitted_date: Date.new(2025, 3, 1)) # 14 days earlier
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(row_date: Date.new(2025, 3, 15)), [ exp ])
    end

    test "debit no match when dates 15 days apart" do
      assert_nil Reconciliation.match_debit_to_expense(
        debit_row(row_date: Date.new(2025, 3, 15)),
        [ expense(submitted_date: Date.new(2025, 2, 28)) ]
      )
    end

    test "debit uses amount excl vat when present" do
      exp = expense(amount: bd("120.00"), amount_excl_vat: bd("100.00"))
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(debit: bd("100.00")), [ exp ])
    end

    test "debit falls back to gross amount when amount_excl_vat is the zero not-yet-known sentinel" do
      # 0/BigDecimal("0") are truthy in Ruby, so a plain || wouldn't fall back
      # to the gross amount here — it would compare against a hard zero and
      # never match any real debit row.
      exp = expense(amount: bd("120.00"), amount_excl_vat: bd("0"))
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(debit: bd("120.00")), [ exp ])
    end

    test "debit skips expense without any reference date" do
      no_dates = expense(submitted_date: nil, payment_confirmed_date: nil)
      assert_nil Reconciliation.match_debit_to_expense(debit_row, [ no_dates ])
    end

    test "debit nominal match is case-insensitive" do
      exp = expense(nominal_code: "abc123")
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(nominal_code: "ABC123"), [ exp ])
    end

    test "debit empty expenses returns nil" do
      assert_nil Reconciliation.match_debit_to_expense(debit_row, [])
    end

    test "debit returns the first matching expense when candidates tie exactly" do
      first = expense
      assert_same first, Reconciliation.match_debit_to_expense(debit_row, [ first, expense ])
    end

    test "debit prefers the candidate with the CLOSEST date, not just the first in the list" do
      # Two same-nominal-code, same-amount expenses submitted around the same
      # time are otherwise indistinguishable — picking whichever happens to
      # come first would risk swapping which one this payment is attributed
      # to. The row's date is 2025-03-15; the second candidate is a much
      # closer match (same day) than the first (10 days off), so it must win
      # even though it's listed second.
      farther = expense(submitted_date: Date.new(2025, 3, 5))
      closer = expense(submitted_date: Date.new(2025, 3, 15))

      matched = Reconciliation.match_debit_to_expense(debit_row(row_date: Date.new(2025, 3, 15)),
                                                       [ farther, closer ])

      assert_same closer, matched
    end

    test "debit uses payment_confirmed_date when submitted date is too far" do
      exp = expense(submitted_date: Date.new(2026, 5, 14), payment_confirmed_date: Date.new(2026, 4, 24))
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row(row_date: Date.new(2026, 4, 24)), [ exp ])
    end

    test "debit no match when both dates outside the window" do
      exp = expense(submitted_date: Date.new(2026, 5, 14), payment_confirmed_date: Date.new(2026, 6, 1))
      assert_nil Reconciliation.match_debit_to_expense(debit_row(row_date: Date.new(2026, 4, 24)), [ exp ])
    end

    # --- match_credit_to_budget -------------------------------------------

    def credit_row(nominal_code: "250000")
      Reconciliation::ActualsRow.new(
        nominal_code: nominal_code, cost_centre: "F40", ref: "INC001", date: Date.new(2025, 3, 15),
        period: "03", narrative: "Grant income", narrative_1: "", debit: bd(0),
        credit: bd("1000.00"), net: bd("-1000.00")
      )
    end

    test "credit exact match" do
      budget = Budget.new(name: "Grant Income", nominal_code: "250000")
      assert_same budget, Reconciliation.match_credit_to_budget(credit_row, [ budget ])
    end

    test "credit no match on wrong nominal" do
      budget = Budget.new(name: "Income", nominal_code: "250000")
      assert_nil Reconciliation.match_credit_to_budget(credit_row(nominal_code: "999999"), [ budget ])
    end

    test "credit match is case-insensitive" do
      budget = Budget.new(name: "Income", nominal_code: "abc123")
      assert_same budget, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "ABC123"), [ budget ])
    end

    test "credit empty budgets returns nil" do
      assert_nil Reconciliation.match_credit_to_budget(credit_row, [])
    end

    test "credit returns the correct budget among several" do
      wrong = Budget.new(name: "Wrong", nominal_code: "100000")
      right = Budget.new(name: "Correct", nominal_code: "250000")
      assert_same right, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "250000"), [ wrong, right ])
    end

    # --- detect_offsetting_pairs -------------------------------------------
    #
    # The fixtures below are ANONYMISED reproductions of the pair shapes in a
    # real EUSA F40 export (309 rows). Nominal codes, dates, periods, ref
    # formats and amounts keep the real structure because that is exactly what
    # the heuristic keys on; every narrative and payee is invented.
    #
    #   Shape 1  same-ref accrual <-> reversal: same nominal, same date,
    #            periods differ (accrual booked in one period, released in the
    #            next). Narratives share a long prefix but diverge mid-string
    #            ("... accrual ..." vs "... reversal ..."). Scores 7.
    #   Shape 2  two journal legs on the SAME nominal with DIFFERENT refs, same
    #            date and period, narratives agreeing on their prefix. Scores
    #            exactly 4 (nominal + period + narrative), the floor at which a
    #            pair is proposed without a ref match at all.
    #   Shape 3  cross-month accrual release: same ref and nominal, three
    #            months apart, periods differ. The 92-day gap costs the full
    #            2-point date penalty, so it survives on ref + nominal +
    #            narrative and scores 5.
    #   Collision  a GENUINE spend row whose amount happens to equal shape 1's
    #            (real export: a real 186.23 claim colliding with an unrelated
    #            186.23 reversal). Different nominal, unrelated narrative, 13
    #            days later, and it only shares the period, so it scores 0 and
    #            must be left alone.
    #   Near miss  same nominal and period, different ref, unrelated
    #            narratives, 16 days apart: scores 2 and must NOT be paired.

    # One row in the real Sage export's column order (SAGE_HEADER above).
    def sage_row(nominal:, date:, period:, ref:, narrative:, value:)
      [ nominal, "F40", "", "COST CENTRE ACCOUNT", date, period, ref, narrative, value, "EUSA" ]
        .join("\t")
    end

    ACCRUAL_LEG = { nominal: "431580", date: "24/07/2025", period: "4", ref: "P8838",
                    narrative: "PO 40000123 accrual jul 25 400123", value: "186.23" }.freeze
    REVERSAL_LEG = { nominal: "431580", date: "24/07/2025", period: "5", ref: "P8838",
                     narrative: "PO 40000123 reversal jul 25 400123", value: "-186.23" }.freeze
    JOURNAL_LEG_A = { nominal: "331130", date: "28/09/2025", period: "6", ref: "J000003374",
                      narrative: "Summer season staff costs accrual reversal", value: "11620.00" }.freeze
    JOURNAL_LEG_B = { nominal: "331130", date: "28/09/2025", period: "6", ref: "J000000934",
                      narrative: "Summer season staff costs accrual", value: "-11620.00" }.freeze
    CROSS_MONTH_LEG_A = { nominal: "331300", date: "27/04/2025", period: "1", ref: "J000000884",
                          narrative: "Venue hire accrual to be released", value: "35775.84" }.freeze
    CROSS_MONTH_LEG_B = { nominal: "331300", date: "28/07/2025", period: "5", ref: "J000000884",
                          narrative: "Venue hire accrual to be released", value: "-35775.84" }.freeze
    COLLIDING_SPEND = { nominal: "435499", date: "06/08/2025", period: "5", ref: "BACS",
                        narrative: "Green room supplies", value: "186.23" }.freeze
    NEAR_MISS_DEBIT = { nominal: "432320", date: "12/05/2025", period: "2", ref: "BACS",
                        narrative: "Rehearsal room hire deposit", value: "200.00" }.freeze
    NEAR_MISS_CREDIT = { nominal: "432320", date: "28/05/2025", period: "2", ref: "1137",
                         narrative: "PI 40000456 1234567890", value: "-200.00" }.freeze

    REAL_SHAPES = [ ACCRUAL_LEG, REVERSAL_LEG, JOURNAL_LEG_A, JOURNAL_LEG_B,
                    CROSS_MONTH_LEG_A, CROSS_MONTH_LEG_B, COLLIDING_SPEND,
                    NEAR_MISS_DEBIT, NEAR_MISS_CREDIT ].freeze

    def parse_shapes(shapes)
      text = ([ SAGE_HEADER ] + shapes.map { |s| sage_row(**s) }).join("\n")
      Reconciliation.parse_actuals_rows(text, cost_centre_code: "F40")
    end

    def pair_narratives(pair)
      [ pair.debit_row.narrative, pair.credit_row.narrative ]
    end

    test "detect_offsetting_pairs proposes the three real pair shapes and nothing else" do
      pairs, remaining = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))

      assert_equal 3, pairs.size
      assert_equal [ [ ACCRUAL_LEG[:narrative], REVERSAL_LEG[:narrative] ],
                     [ CROSS_MONTH_LEG_A[:narrative], CROSS_MONTH_LEG_B[:narrative] ],
                     [ JOURNAL_LEG_A[:narrative], JOURNAL_LEG_B[:narrative] ] ],
                   pairs.map { |pair| pair_narratives(pair) },
                   "highest-scoring pair first: 7 (same ref), 5 (cross-month), 4 (nominal+period+narrative)"
      assert_equal [ 7, 5, 4 ], pairs.map(&:score)
      assert_equal [ COLLIDING_SPEND[:narrative], NEAR_MISS_DEBIT[:narrative],
                     NEAR_MISS_CREDIT[:narrative] ],
                   remaining.map(&:narrative),
                   "the colliding genuine spend and the near-miss pair stay in the working set"
    end

    test "detect_offsetting_pairs orients each pair debit leg first" do
      pairs, = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))

      pairs.each do |pair|
        assert_operator pair.debit_row.debit, :>, 0, "the debit leg carries the positive amount"
        assert_operator pair.credit_row.credit, :>, 0, "the credit leg carries the offsetting amount"
      end
    end

    test "detect_offsetting_pairs leaves an amount collision with a genuine row unpaired" do
      pairs, remaining = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ ACCRUAL_LEG, REVERSAL_LEG, COLLIDING_SPEND ])
      )

      assert_equal 1, pairs.size
      assert_equal [ ACCRUAL_LEG[:narrative], REVERSAL_LEG[:narrative] ], pair_narratives(pairs.first)
      assert_equal [ COLLIDING_SPEND[:narrative] ], remaining.map(&:narrative)
    end

    test "detect_offsetting_pairs leaves a same-nominal near miss unpaired" do
      pairs, remaining = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ NEAR_MISS_DEBIT, NEAR_MISS_CREDIT ])
      )

      assert_empty pairs, "nominal + period alone (score 2) is below the threshold"
      assert_equal 2, remaining.size
    end

    # Greed matters when two eligible pairs compete for the same leg: the
    # stronger evidence must win and the loser must be left unmatched rather
    # than paired with whatever is left over.
    test "detect_offsetting_pairs consumes each row at most once, best score first" do
      weaker_claimant = { nominal: "431580", date: "24/07/2025", period: "5", ref: "BACS",
                          narrative: "PO 40000123 accrual jul 25 400123", value: "186.23" }
      pairs, remaining = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ weaker_claimant, ACCRUAL_LEG, REVERSAL_LEG ])
      )

      assert_equal 1, pairs.size
      assert_equal [ ACCRUAL_LEG[:narrative], REVERSAL_LEG[:narrative] ], pair_narratives(pairs.first)
      assert_equal 7, pairs.first.score
      assert_equal [ weaker_claimant[:narrative] ], remaining.map(&:narrative),
                   "the weaker claimant (score 4) loses the reversal leg and stays unmatched"
    end

    test "detect_offsetting_pairs needs the exact same absolute amount" do
      penny_off = REVERSAL_LEG.merge(value: "-186.24")
      pairs, remaining = Reconciliation.detect_offsetting_pairs(parse_shapes([ ACCRUAL_LEG, penny_off ]))

      assert_empty pairs, "a penny apart is a different transaction, not an offset"
      assert_equal 2, remaining.size
    end

    test "detect_offsetting_pairs never pairs two rows of the same sign" do
      same_sign = REVERSAL_LEG.merge(value: "186.23")
      pairs, = Reconciliation.detect_offsetting_pairs(parse_shapes([ ACCRUAL_LEG, same_sign ]))

      assert_empty pairs
    end

    test "detect_offsetting_pairs never pairs across financial years" do
      # 31 March and 1 April sit either side of the April-based financial year
      # boundary, so these are two different years' books despite everything
      # else matching.
      last_year = ACCRUAL_LEG.merge(date: "31/03/2025", period: "12")
      this_year = REVERSAL_LEG.merge(date: "01/04/2025", period: "1")
      pairs, remaining = Reconciliation.detect_offsetting_pairs(parse_shapes([ last_year, this_year ]))

      assert_empty pairs
      assert_equal 2, remaining.size
    end

    test "detect_offsetting_pairs ignores rows that net to zero" do
      zero_debit = ACCRUAL_LEG.merge(value: "0.00")
      zero_credit = REVERSAL_LEG.merge(value: "-0.00")
      pairs, remaining = Reconciliation.detect_offsetting_pairs(parse_shapes([ zero_debit, zero_credit ]))

      assert_empty pairs
      assert_equal 2, remaining.size
    end

    test "a pair key is stable across re-parses of the same paste" do
      first_pairs, = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))
      second_pairs, = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))

      assert_equal first_pairs.map(&:key), second_pairs.map(&:key)
      assert_equal 3, first_pairs.map(&:key).uniq.size, "each proposed pair gets its own key"
    end

    test "a pair key does not depend on the row's position in the paste" do
      forwards, = Reconciliation.detect_offsetting_pairs(parse_shapes([ ACCRUAL_LEG, REVERSAL_LEG ]))
      with_lead_row, = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ COLLIDING_SPEND, ACCRUAL_LEG, REVERSAL_LEG ])
      )

      assert_equal forwards.first.key, with_lead_row.first.key
    end

    # Two identical accruals and two identical reversals are FOUR real
    # transactions, so the two pairs they form must stay distinguishable. On a
    # content-only key they collapse into one, and unticking either one of them
    # in the preview offsets both — stamping a genuine transaction as
    # bookkeeping noise.
    test "two byte-identical pairs in one paste get distinct keys" do
      pairs, remaining = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ ACCRUAL_LEG, REVERSAL_LEG, ACCRUAL_LEG, REVERSAL_LEG ])
      )

      assert_equal 2, pairs.size
      assert_empty remaining
      assert_equal 2, pairs.map(&:key).uniq.size, "each pair of real rows needs its own key"
    end

    # The occurrence counter that keeps duplicates apart counts only rows with
    # identical CONTENT, so it survives the re-parse the same way the digest
    # does: adding unrelated rows around a duplicated pair leaves both keys
    # untouched.
    test "duplicate pair keys are stable when unrelated rows surround them" do
      duplicated = [ ACCRUAL_LEG, REVERSAL_LEG, ACCRUAL_LEG, REVERSAL_LEG ]
      bare, = Reconciliation.detect_offsetting_pairs(parse_shapes(duplicated))
      padded, = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ COLLIDING_SPEND ] + duplicated + [ NEAR_MISS_DEBIT ])
      )

      assert_equal bare.map(&:key), padded.map(&:key)
    end
  end
end
