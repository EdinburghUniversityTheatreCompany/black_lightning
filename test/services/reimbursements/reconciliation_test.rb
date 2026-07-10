require "test_helper"
require "bigdecimal"

module Reimbursements
  # Ported from bedlam-bacs tests/test_reconciliation.py (parse + dedup half;
  # the match_* fns port alongside the extended Expense/Budget POROs).
  class ReconciliationTest < ActiveSupport::TestCase
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
        record_id: "recE1", auto_number: 1, status: Status::SUBMITTED,
        amount: amount, amount_excl_vat: amount_excl_vat,
        budget: Budget.new(record_id: "recB1", name: "Production", nominal_code: nominal_code),
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

    test "debit returns the first matching expense" do
      first = expense
      assert_same first, Reconciliation.match_debit_to_expense(debit_row, [ first, expense ])
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
      budget = Budget.new(record_id: "recB1", name: "Grant Income", nominal_code: "250000")
      assert_same budget, Reconciliation.match_credit_to_budget(credit_row, [ budget ])
    end

    test "credit no match on wrong nominal" do
      budget = Budget.new(record_id: "recB1", name: "Income", nominal_code: "250000")
      assert_nil Reconciliation.match_credit_to_budget(credit_row(nominal_code: "999999"), [ budget ])
    end

    test "credit match is case-insensitive" do
      budget = Budget.new(record_id: "recB1", name: "Income", nominal_code: "abc123")
      assert_same budget, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "ABC123"), [ budget ])
    end

    test "credit empty budgets returns nil" do
      assert_nil Reconciliation.match_credit_to_budget(credit_row, [])
    end

    test "credit returns the correct budget among several" do
      wrong = Budget.new(record_id: "recB1", name: "Wrong", nominal_code: "100000")
      right = Budget.new(record_id: "recB2", name: "Correct", nominal_code: "250000")
      assert_same right, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "250000"), [ wrong, right ])
    end
  end
end
