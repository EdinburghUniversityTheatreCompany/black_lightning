require "test_helper"
require "bigdecimal"

module Reimbursements
  class ReconciliationTest < ActiveSupport::TestCase
    # The pure matchers read the AR models' public interface; built unpersisted.
    Expense = Reimbursements::Expense
    Budget = Reimbursements::Budget

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze
    SAMPLE_ROW = "439999\tF40\tBACS001\t15/03/2025\t03\tAlice Producer\tSome show\t123.45\t\t123.45".freeze
    SAMPLE_CSV_ROW = "439999,F40,BACS001,15/03/2025,03,Alice Producer,Some show,123.45,,123.45".freeze

    def bd(value)
      BigDecimal(value.to_s)
    end

    # --- actuals_row_dedup_key --------------------------------------------

    def dedup_key(debit, credit, nominal: "439999", narrative: "Alice Producer")
      Reconciliation.actuals_row_dedup_key(nominal, narrative, debit, credit)
    end

    test "dedup key treats equivalent spellings of a row as one" do
      assert_equal dedup_key(bd(0), bd(0)), dedup_key(nil, nil)
      assert_equal dedup_key(bd(0), bd(0)), dedup_key(bd("-0.00"), bd("-0.00"))
      assert_equal dedup_key(bd(0), bd("123.45")), dedup_key(nil, bd("123.45"))
      assert_equal dedup_key(bd(0), bd(0)), dedup_key(bd(0), bd(0), narrative: "  Alice Producer  ")
    end

    test "dedup key keeps different rows apart" do
      refute_equal dedup_key(bd("100.00"), bd(0)), dedup_key(bd("200.00"), bd(0))
      refute_equal dedup_key(bd(0), bd(0)), dedup_key(bd(0), bd(0), nominal: "250000")
      refute_equal dedup_key(bd(0), bd(0)), dedup_key(bd(0), bd(0), narrative: "Bob Producer")
      # A Float key would collapse these two onto one value.
      refute_equal dedup_key(bd("9999999999999999.99"), bd(0)), dedup_key(bd("9999999999999999.98"), bd(0))
    end

    # --- parse_actuals_rows: legacy format --------------------------------

    test "blank input parses to no rows" do
      [ "", "   \n  \t  " ].each { |text| assert_empty Reconciliation.parse_actuals_rows(text) }
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

    test "an unreadable date raises, and a two-digit year does not silently land in year 89" do
      %w[15/03/89 not-a-date].each do |date|
        row_text = "439999\tF40\tBACS001\t#{date}\t12\tNarr\tNarr1\t50.00\t\t50.00"
        error = assert_raises(ArgumentError) { Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}") }
        assert_match(/Cannot parse date/, error.message)
      end
    end

    test "amounts with commas are parsed" do
      row_text = "439999\tF40\tBACS001\t15/03/2025\t03\tNarr\tNarr1\t1,234.56\t\t1,234.56"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{row_text}")
      assert_equal bd("1234.56"), rows.first.debit
    end

    # The parser does not filter by cost centre: every row comes back with its own code, and
    # ActualsAttribution decides what is ours.

    test "a paste spanning several cost centres returns every row" do
      bed = "439999\tBED\tBACS001\t15/03/2025\t03\tAlice\tShow\t10.00\t\t10.00"
      other = "439999\tF99\tBACS002\t15/03/2025\t03\tBob\tOther\t50.00\t\t50.00"
      blank = "439999\t\tBACS003\t15/03/2025\t03\tCarol\tShow\t5.00\t\t5.00"
      rows = Reconciliation.parse_actuals_rows("#{HEADER}\n#{SAMPLE_ROW}\n#{bed}\n#{other}\n#{blank}")
      assert_equal [ "F40", "BED", "F99", "" ], rows.map(&:cost_centre)
    end

    # Some exports omit the column: that is a paste whose rows have no cost centre, not a malformed one.
    test "a header with no Cost Centre column parses, leaving every code blank" do
      header = "Nominal\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet"
      row_text = "439999\tBACS001\t15/03/2025\t03\tAlice\tShow\t123.45\t\t123.45"
      rows = Reconciliation.parse_actuals_rows("#{header}\n#{row_text}")
      assert_equal 1, rows.length
      assert_equal "", rows.first.cost_centre
      assert_equal bd("123.45"), rows.first.debit
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

    test "sage field mapping" do
      row = Reconciliation.parse_actuals_rows("#{SAGE_HEADER}\n#{SAGE_DEBIT_ROW}").first
      assert_equal "431580", row.nominal_code
      assert_equal "F40", row.cost_centre
      assert_equal "BACS", row.ref
      assert_equal Date.new(2026, 4, 24), row.date
      # Sage writes the month unpadded; the parser normalises it to the canonical spelling.
      assert_equal "01", row.period
      assert_equal "EN-LIANG LEE - TECH PC GRAPHICS CARD", row.narrative
      assert_equal "", row.narrative_1
    end

    test "sage real data sample" do
      sample = [
        SAGE_HEADER,
        SAGE_DEBIT_ROW,
        "431580\tF40\t\tEQUIPMENT HIRE & PURCHASE\t24/04/2026\t1\tBACS\tEN-LIANG LEE - TECH PC MOTHERBOARD\t85.38\tEUSA",
        SAGE_CREDIT_ROW
      ].join("\n")
      rows = Reconciliation.parse_actuals_rows(sample)
      assert_equal 3, rows.length
      assert_equal bd("118.24"), rows[0].debit
      assert_equal bd(0), rows[0].credit
      assert_equal bd("118.24"), rows[0].net
      assert_equal bd("85.38"), rows[1].debit
      assert_equal bd(0), rows[2].debit
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

    # --- The international rail ---------------------------------------------
    #
    # An international claim's stored amount is finance's GBP ESTIMATE; the actual is what EUSA's bank
    # charged after the FX spread, pounds apart on a few hundred, so the penny window would leave it
    # permanently unmatched. Nothing on the actuals row says the rail: each expense knows its own.

    def international_expense(amount: bd("230.00"), **attrs)
      expense(amount: amount, **attrs).tap do |e|
        e.payment_method = Expense::PAYMENT_METHOD_INTERNATIONAL
        e.foreign_amount = bd("266.69")
        e.foreign_currency = Expense::CURRENCY_EUR
      end
    end

    # A tiny claim's percentage window would be sub-penny, narrower than the UK floor: 0.10 must still
    # match 0.11.
    test "an international claim matches within a percentage window, never narrower than a penny" do
      { "230.00" => "236.10", "4000.00" => "4108.00", "0.10" => "0.11" }.each do |estimate, charged|
        exp = international_expense(amount: bd(estimate))
        assert_same exp, Reconciliation.match_debit_to_expense(debit_row(debit: bd(charged)), [ exp ]),
                    "#{estimate} estimated, #{charged} charged"
      end
      assert_nil Reconciliation.match_debit_to_expense(debit_row(debit: bd("299.00")), [ international_expense ]),
                 "30% out is a different payment"
    end

    # A false match stamps one claim's spend onto another and every rollup repeats it, so the wider
    # window is not given to the UK rail.
    test "a UK claim keeps the penny window" do
      exp = expense(amount: bd("230.00"))

      assert_nil Reconciliation.match_debit_to_expense(debit_row(debit: bd("236.10")), [ exp ])
    end

    test "debit exact match" do
      exp = expense
      assert_same exp, Reconciliation.match_debit_to_expense(debit_row, [ exp ])
    end

    test "debit no match on wrong nominal" do
      assert_nil Reconciliation.match_debit_to_expense(debit_row(nominal_code: "999999"), [ expense ])
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
      # 0 is truthy, so a plain || would compare against a hard zero and never match.
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

    test "debit prefers the candidate with the CLOSEST date, not just the first in the list" do
      # Two same-nominal, same-amount expenses are otherwise indistinguishable: the closer date
      # (same day) must win over the first listed (10 days off).
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

    test "credit no match on wrong nominal" do
      budget = Budget.new(name: "Income", nominal_code: "250000")
      assert_nil Reconciliation.match_credit_to_budget(credit_row(nominal_code: "999999"), [ budget ])
    end

    test "credit match is case-insensitive" do
      budget = Budget.new(name: "Income", nominal_code: "abc123")
      assert_same budget, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "ABC123"), [ budget ])
    end

    test "credit returns the correct budget among several" do
      wrong = Budget.new(name: "Wrong", nominal_code: "100000")
      right = Budget.new(name: "Correct", nominal_code: "250000")
      assert_same right, Reconciliation.match_credit_to_budget(credit_row(nominal_code: "250000"), [ wrong, right ])
    end

    # --- detect_offsetting_pairs -------------------------------------------
    # The fixtures are ANONYMISED reproductions of the pair shapes in a real 309-row EUSA F40 export:
    # codes, dates, periods, refs and amounts keep the real structure the heuristic keys on; narratives
    # and payees are invented.
    #
    #   Shape 1  same-ref accrual <-> reversal: same nominal and date, periods differ, narratives share
    #            a long prefix and diverge mid-string. Scores 7.
    #   Shape 2  two journal legs on one nominal, different refs, same date and period, narratives
    #            agreeing on a prefix. Scores exactly 4, the floor with no ref match at all.
    #   Shape 3  cross-month accrual release: same ref and nominal three months apart. The 92-day gap
    #            costs the full 2 points, so it scores 5.
    #   Collision  a GENUINE spend row whose amount equals shape 1's (a real 186.23 claim colliding with
    #            an unrelated 186.23 reversal). Different nominal, unrelated narrative: scores 0, left alone.
    #   Near miss  same nominal and period, different ref, unrelated narratives, 16 days apart: scores 2,
    #            must NOT be paired.

    # One row in the real Sage export's column order (SAGE_HEADER above).
    def sage_row(nominal:, date:, period:, ref:, narrative:, value:, cost_centre: "F40")
      [ nominal, cost_centre, "", "COST CENTRE ACCOUNT", date, period, ref, narrative, value, "EUSA" ]
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

    # A Sage payment-run reference is stamped across every row of a run, so a cost and an unrelated
    # income of the same size share it: ref (4) + period (1) = 5 clears the floor. Same nominal code is
    # therefore a hard requirement, not a scoring signal.
    CROSS_NOMINAL_DEBIT = { nominal: "041000", date: "12/06/2025", period: "3", ref: "BACS0099",
                            narrative: "Lighting hire for the summer run", value: "1234.56" }.freeze
    CROSS_NOMINAL_CREDIT = { nominal: "081000", date: "12/06/2025", period: "3", ref: "BACS0099",
                             narrative: "Ticket income june transfer", value: "-1234.56" }.freeze

    REAL_SHAPES = [ ACCRUAL_LEG, REVERSAL_LEG, JOURNAL_LEG_A, JOURNAL_LEG_B,
                    CROSS_MONTH_LEG_A, CROSS_MONTH_LEG_B, COLLIDING_SPEND,
                    NEAR_MISS_DEBIT, NEAR_MISS_CREDIT ].freeze

    def parse_shapes(shapes)
      text = ([ SAGE_HEADER ] + shapes.map { |s| sage_row(**s) }).join("\n")
      Reconciliation.parse_actuals_rows(text)
    end

    def pair_narratives(pair)
      [ pair.debit_row.narrative, pair.credit_row.narrative ]
    end

    test "detect_offsetting_pairs proposes the three real pair shapes and nothing else" do
      pairs = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))

      assert_equal 3, pairs.size
      assert_equal [ [ ACCRUAL_LEG[:narrative], REVERSAL_LEG[:narrative] ],
                     [ CROSS_MONTH_LEG_A[:narrative], CROSS_MONTH_LEG_B[:narrative] ],
                     [ JOURNAL_LEG_A[:narrative], JOURNAL_LEG_B[:narrative] ] ],
                   pairs.map { |pair| pair_narratives(pair) },
                   "highest-scoring pair first: 7 (same ref), 5 (cross-month), 4 (nominal+period+narrative)"
      assert_equal [ 7, 5, 4 ], pairs.map(&:score)
    end

    test "detect_offsetting_pairs orients each pair debit leg first" do
      pairs = Reconciliation.detect_offsetting_pairs(parse_shapes(REAL_SHAPES))

      pairs.each do |pair|
        assert_operator pair.debit_row.debit, :>, 0, "the debit leg carries the positive amount"
        assert_operator pair.credit_row.credit, :>, 0, "the credit leg carries the offsetting amount"
      end
    end

    # When two eligible pairs compete for a leg, the stronger evidence wins and the loser stays unmatched.
    test "detect_offsetting_pairs consumes each row at most once, best score first" do
      weaker_claimant = { nominal: "431580", date: "24/07/2025", period: "5", ref: "BACS",
                          narrative: "PO 40000123 accrual jul 25 400123", value: "186.23" }
      pairs = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ weaker_claimant, ACCRUAL_LEG, REVERSAL_LEG ])
      )

      assert_equal 1, pairs.size, "the weaker claimant (score 4) loses the reversal leg and stays unpaired"
      assert_equal [ ACCRUAL_LEG[:narrative], REVERSAL_LEG[:narrative] ], pair_narratives(pairs.first)
      assert_equal 7, pairs.first.score
    end

    # Each hard gate refuses a pair however well it would score. The cost-centre gate stops two pots'
    # unrelated transactions cancelling and hiding real spend from both rollups.
    {
      "different nominal codes" => [ CROSS_NOMINAL_DEBIT, CROSS_NOMINAL_CREDIT ],
      "different cost centres" => [ ACCRUAL_LEG, REVERSAL_LEG.merge(cost_centre: "BED") ],
      "blank cost centres" => [ ACCRUAL_LEG.merge(cost_centre: ""), REVERSAL_LEG.merge(cost_centre: "") ],
      "blank nominal codes" => [ ACCRUAL_LEG.merge(nominal: ""), REVERSAL_LEG.merge(nominal: "") ],
      "amounts a penny apart" => [ ACCRUAL_LEG, REVERSAL_LEG.merge(value: "-186.24") ],
      "the same sign" => [ ACCRUAL_LEG, REVERSAL_LEG.merge(value: "186.23") ],
      "different financial years" => [ ACCRUAL_LEG.merge(date: "31/03/2025", period: "12"),
                                       REVERSAL_LEG.merge(date: "01/04/2025", period: "1") ],
      "zero amounts" => [ ACCRUAL_LEG.merge(value: "0.00"), REVERSAL_LEG.merge(value: "-0.00") ]
    }.each do |gate, shapes|
      test "detect_offsetting_pairs never pairs rows with #{gate}" do
        assert_empty Reconciliation.detect_offsetting_pairs(parse_shapes(shapes))
      end
    end

    # ...unless the caller has resolved attribution: blank-code rows an operator assigned to one pot
    # ARE in it, and pair like any other.
    test "detect_offsetting_pairs pairs blank-code rows the caller has attributed to one centre" do
      rows = parse_shapes([ ACCRUAL_LEG.merge(cost_centre: ""), REVERSAL_LEG.merge(cost_centre: "") ])
      pairs = Reconciliation.detect_offsetting_pairs(rows, cost_centres: %w[7 7])

      assert_equal 1, pairs.size
    end

    test "detect_offsetting_pairs honours caller-supplied identities over the export's codes" do
      rows = parse_shapes([ ACCRUAL_LEG, REVERSAL_LEG ])
      pairs = Reconciliation.detect_offsetting_pairs(rows, cost_centres: %w[7 8])

      assert_empty pairs, "the caller attributed these two identical-looking codes to different pots"
    end

    # Two identical accruals and two identical reversals are FOUR transactions, so their two pairs must
    # stay distinguishable: on a content-only key, unticking either would offset both.
    test "two byte-identical pairs in one paste get distinct keys" do
      pairs = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ ACCRUAL_LEG, REVERSAL_LEG, ACCRUAL_LEG, REVERSAL_LEG ])
      )

      assert_equal 2, pairs.size
      assert_equal 2, pairs.map(&:key).uniq.size, "each pair of real rows needs its own key"
    end

    # The occurrence counter counts identical CONTENT only, so unrelated rows around a duplicated pair
    # leave both keys untouched.
    test "duplicate pair keys are stable when unrelated rows surround them" do
      duplicated = [ ACCRUAL_LEG, REVERSAL_LEG, ACCRUAL_LEG, REVERSAL_LEG ]
      bare = Reconciliation.detect_offsetting_pairs(parse_shapes(duplicated))
      padded = Reconciliation.detect_offsetting_pairs(
        parse_shapes([ COLLIDING_SPEND ] + duplicated + [ NEAR_MISS_DEBIT ])
      )

      assert_equal bare.map(&:key), padded.map(&:key)
    end
  end
end
