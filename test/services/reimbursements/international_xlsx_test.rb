require "test_helper"
require "rubyXL" # InternationalXlsx#generate requires it lazily; this test parses output directly

module Reimbursements
  class InternationalXlsxTest < ActiveSupport::TestCase
    Payment = InternationalXlsx::Payment

    def payment(**overrides)
      Payment.new(
        payee_name: "Ausland GmbH", amount: BigDecimal("266.69"), currency: "EUR",
        description: "Invoice 4711 (festival insurance)", date_required: Date.new(2026, 10, 1),
        nominal_code: "432540", cost_centre: "F40",
        bic: "DEUTDEFF500", iban: "DE89370400440532013000", **overrides
      )
    end

    def parsed(bytes)
      RubyXL::Parser.parse_buffer(bytes)["FORM"]
    end

    def cell(sheet, row, col)
      sheet.sheet_data[row][col]
    end

    test "writes the eight payment cells" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "Ausland GmbH", cell(sheet, 7, 2).value
      assert_equal "Invoice 4711 (festival insurance)", cell(sheet, 8, 2).value
      assert_in_delta 266.69, cell(sheet, 9, 2).value, 0.001
      assert_equal "432540", cell(sheet, 10, 2).value
      assert_equal "F40", cell(sheet, 10, 4).value
      assert_equal "DEUTDEFF500", cell(sheet, 11, 2).value
      assert_equal "DE89370400440532013000", cell(sheet, 11, 4).value
    end

    test "the date required is written as a real date" do
      sheet = parsed(InternationalXlsx.new.generate(payment))
      value = cell(sheet, 9, 4).value

      # rubyXL hands back a Date/DateTime for a date-formatted cell; either way
      # it must be a date and not the ISO string, or Excel shows text where the
      # template formats a date.
      assert_kind_of Date, value.respond_to?(:to_date) ? value.to_date : value
      assert_equal Date.new(2026, 10, 1), value.to_date
    end

    # The three authorisation formulas (C18/C19/E18) pick the signatory from
    # C10. They read it as a NUMBER, so writing the amount as a string would
    # silently break all three and hand EUSA a form naming no authoriser.
    test "the amount is numeric so the authorisation formulas still resolve" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_kind_of Numeric, cell(sheet, 9, 2).value
      assert_equal "IF(C10<=999.99, LISTS!A9,LISTS!A12)", cell(sheet, 17, 2).formula.expression
      assert_equal "IF(C10>=1000,LISTS!A11,LISTS!A12)", cell(sheet, 18, 2).formula.expression
      assert_equal "IF(C10>=10000,LISTS!A13,LISTS!A12)", cell(sheet, 17, 4).formula.expression
    end

    # rubyXL's add_cell REPLACES the cell and drops the style the template
    # applied, so the amount would render as a bare number in a form whose
    # every other figure is currency-formatted.
    test "writing preserves the template's own cell formatting" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal '"£"#,##0.00', cell(sheet, 9, 2).number_format.format_code
    end

    test "BIC and IBAN are written as text" do
      # The template carries leftover sort-code/account-number numeric formats
      # on these two cells from whichever form it was copied out of.
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "@", cell(sheet, 11, 2).number_format.format_code
      assert_equal "@", cell(sheet, 11, 4).number_format.format_code
    end

    test "the IBAN is written grouped, as a human checks it" do
      sheet = parsed(InternationalXlsx.new.generate(payment, format_iban: true))

      assert_equal "DE89 3704 0044 0532 0130 00", cell(sheet, 11, 4).value
    end

    # xlsx caches each formula's last computed value beside the formula, and
    # the template's cache holds the answers EUSA's SAMPLE payment produced.
    # Writing a new amount does not update them, so without a recalculation
    # request a reader renders the sample's authoriser: a EUR 1,266.69 form
    # would name a Finance Team Co-ordinator where EUSA's own rule sends
    # anything over £1,000 to the Head of Finance.
    test "the workbook asks every reader to recalculate on open" do
      workbook = RubyXL::Parser.parse_buffer(InternationalXlsx.new.generate(payment))

      assert workbook.calc_pr.full_calc_on_load,
             "without fullCalcOnLoad the authorisation row shows the sample payment's signatory"
    end

    # Belt and braces to the flag above: a reader that ignores fullCalcOnLoad
    # (LibreOffice's headless convert, verified) would otherwise render the
    # cached value, which is the SAMPLE's authoriser. With the cache dropped
    # such a reader shows a blank authorisation row — "not filled in", which
    # prompts a human, rather than a confident wrong answer that does not.
    test "no formula carries a stale cached value from the sample payment" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      [ [ 17, 2 ], [ 18, 2 ], [ 17, 4 ] ].each do |row, column|
        cell = cell(sheet, row, column)
        assert cell.formula, "expected a formula at #{row},#{column}"
        assert_empty cell.value.to_s,
                     "the cached value at #{row},#{column} is the sample payment's answer"
      end
    end

    test "the template's own furniture is left alone" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "PAYEE:", cell(sheet, 7, 1).value
      assert_equal "NOT REQUIRED", cell(sheet, 13, 2).value
      assert_equal "YES", cell(sheet, 13, 4).value
      assert_equal "HEAD OF FINANCE AND BUSINESS REPORTING", cell(sheet, 21, 2).value
    end

    test "the LISTS sheet the formulas depend on survives" do
      workbook = RubyXL::Parser.parse_buffer(InternationalXlsx.new.generate(payment))

      assert_equal %w[FORM LISTS], workbook.worksheets.map(&:sheet_name)
      assert_equal "FINANCE TEAM CO-ORDINATOR or FINANCE ANALYST",
                   workbook["LISTS"].sheet_data[8][0].value
    end

    # Same rule as the BACS spreadsheet: payee and description are
    # submitter-controlled free text landing in a spreadsheet EUSA opens.
    test "formula-triggering free text is neutralised" do
      sheet = parsed(InternationalXlsx.new.generate(
        payment(payee_name: "=cmd|'/c calc'!A1", description: "+SUM(A1:A9)")
      ))

      assert_equal "'=cmd|'/c calc'!A1", cell(sheet, 7, 2).value
      assert_equal "'+SUM(A1:A9)", cell(sheet, 8, 2).value
    end

    # --- Refusals -----------------------------------------------------------
    #
    # Each of these is a form EUSA could not act on, and a form that reaches
    # them wrong costs a round trip through a finance team that batches its
    # payment runs. Refusing is cheap; a wrong form is not.

    test "refuses a blank cost centre" do
      # Mirrors BacsXlsx: a termtime payment silently stamped with the Fringe
      # code books the spend against the wrong pot.
      error = assert_raises(InternationalXlsx::TemplateError) do
        InternationalXlsx.new.generate(payment(cost_centre: " "))
      end
      assert_match(/cost.centre/i, error.message)
    end

    test "refuses a blank IBAN or BIC" do
      assert_raises(InternationalXlsx::TemplateError) { InternationalXlsx.new.generate(payment(iban: "")) }
      assert_raises(InternationalXlsx::TemplateError) { InternationalXlsx.new.generate(payment(bic: nil)) }
    end

    test "refuses an IBAN that fails its check digits" do
      # The form is the last point anything looks at the number before EUSA's
      # bank does, and by then the money has moved.
      error = assert_raises(InternationalXlsx::TemplateError) do
        InternationalXlsx.new.generate(payment(iban: "DE88370400440532013000"))
      end
      assert_match(/IBAN/i, error.message)
    end

    test "refuses a missing or zero amount" do
      assert_raises(InternationalXlsx::TemplateError) { InternationalXlsx.new.generate(payment(amount: nil)) }
      assert_raises(InternationalXlsx::TemplateError) { InternationalXlsx.new.generate(payment(amount: 0)) }
    end

    test "refuses a missing template" do
      error = assert_raises(InternationalXlsx::TemplateError) do
        InternationalXlsx.new(template_path: Rails.root.join("nope.xlsx"))
      end
      assert_match(/not found/i, error.message)
    end

    test "one instance produces many independent forms" do
      builder = InternationalXlsx.new
      first = parsed(builder.generate(payment(payee_name: "First Supplier")))
      second = parsed(builder.generate(payment(payee_name: "Second Supplier")))

      assert_equal "First Supplier", cell(first, 7, 2).value
      assert_equal "Second Supplier", cell(second, 7, 2).value
    end
  end
end
