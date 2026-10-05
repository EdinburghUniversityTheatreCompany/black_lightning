require "test_helper"
require "rubyXL" # generate requires it lazily; this test parses the output itself

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

    # A1 references, so an assertion can be checked against EUSA's form by eye.
    def cell(sheet, ref)
      column = ref[/\A[A-Z]+/].chars.reduce(0) { |n, ch| (n * 26) + (ch.ord - 64) } - 1
      sheet.sheet_data[ref[/\d+\z/].to_i - 1][column]
    end

    test "writes the nine payment cells" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "Ausland GmbH", cell(sheet, "C8").value
      assert_equal "Invoice 4711 (festival insurance)", cell(sheet, "C9").value
      assert_in_delta 266.69, cell(sheet, "C10").value, 0.001
      assert_equal "EUR", cell(sheet, "C11").value
      assert_equal "432540", cell(sheet, "C12").value
      assert_equal "F40", cell(sheet, "E12").value
      assert_equal "DEUTDEFF500", cell(sheet, "C13").value
      assert_equal "DE89370400440532013000", cell(sheet, "E13").value
    end

    # --- Currency ------------------------------------------------------------

    test "the currency is written as text" do
      # C11 arrives with a "£" number format copied from an amount cell.
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "@", cell(sheet, "C11").number_format.format_code
    end

    test "a non-euro currency is carried through" do
      sheet = parsed(InternationalXlsx.new.generate(payment(currency: "USD", amount: BigDecimal("500"))))

      assert_equal "USD", cell(sheet, "C11").value
      assert_in_delta 500.0, cell(sheet, "C10").value, 0.001
    end

    test "the currency is normalised to an upper-case code" do
      sheet = parsed(InternationalXlsx.new.generate(payment(currency: " usd ")))

      assert_equal "USD", cell(sheet, "C11").value
    end

    test "refuses a blank currency" do
      # The amount label names no currency, so a blank leaves no unit at all.
      error = assert_raises(InternationalXlsx::TemplateError) do
        InternationalXlsx.new.generate(payment(currency: ""))
      end
      assert_match(/currency/i, error.message)
    end

    # The template's "£" would print a EUR payment as "£266.69" above a cell reading EUR.
    test "a non-sterling amount drops the pound symbol" do
      sheet = parsed(InternationalXlsx.new.generate(payment(currency: "EUR")))

      assert_equal "#,##0.00", cell(sheet, "C10").number_format.format_code
    end

    test "a sterling amount keeps the pound symbol" do
      # A supplier can invoice in GBP, and then the template's format is right.
      sheet = parsed(InternationalXlsx.new.generate(payment(currency: "GBP")))

      assert_equal '"£"#,##0.00', cell(sheet, "C10").number_format.format_code
    end

    test "the date required is written as a real date" do
      sheet = parsed(InternationalXlsx.new.generate(payment))
      value = cell(sheet, "E10").value

      # rubyXL returns a Date or a DateTime; either way not the ISO string.
      assert_kind_of Date, value.respond_to?(:to_date) ? value.to_date : value
      assert_equal Date.new(2026, 10, 1), value.to_date
    end

    # The authorisation formulas read C10 as a NUMBER: a string breaks all three.
    test "the amount is numeric so the authorisation formulas still resolve" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_kind_of Numeric, cell(sheet, "C10").value
      assert_equal "IF(C10<=999.99, LISTS!A9,LISTS!A12)", cell(sheet, "C19").formula.expression
      assert_equal "IF(C10>=1000,LISTS!A11,LISTS!A12)", cell(sheet, "C20").formula.expression
      assert_equal "IF(C10>=10000,LISTS!A13,LISTS!A12)", cell(sheet, "E19").formula.expression
    end

    # add_cell would drop the template's style: the date would show as a serial number.
    test "writing preserves the template's own cell formatting" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "m/d/yyyy", cell(sheet, "E10").number_format.format_code
    end

    test "BIC and IBAN are written as text" do
      # The template leaves sort-code and account-number formats on these cells.
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "@", cell(sheet, "C13").number_format.format_code
      assert_equal "@", cell(sheet, "E13").number_format.format_code
    end

    test "the IBAN is written grouped, as a human checks it" do
      sheet = parsed(InternationalXlsx.new.generate(payment, format_iban: true))

      assert_equal "DE89 3704 0044 0532 0130 00", cell(sheet, "E13").value
    end

    # The template caches the SAMPLE payment's formula answers, so without a
    # recalculation a reader shows the sample's authoriser.
    test "the workbook asks every reader to recalculate on open" do
      workbook = RubyXL::Parser.parse_buffer(InternationalXlsx.new.generate(payment))

      assert workbook.calc_pr.full_calc_on_load,
             "without fullCalcOnLoad the authorisation row shows the sample payment's signatory"
    end

    # For a reader that ignores fullCalcOnLoad (LibreOffice): a blank authoriser
    # prompts a human, a stale one does not.
    test "no formula carries a stale cached value from the sample payment" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      %w[C19 C20 E19].each do |ref|
        cell = cell(sheet, ref)
        assert cell.formula, "expected a formula at #{ref}"
        assert_empty cell.value.to_s, "the cached value at #{ref} is a stale answer"
      end
    end

    test "the template's own furniture is left alone" do
      sheet = parsed(InternationalXlsx.new.generate(payment))

      assert_equal "PAYEE:", cell(sheet, "B8").value
      assert_equal "NOT REQUIRED", cell(sheet, "C15").value
      assert_equal "YES", cell(sheet, "E15").value
      assert_equal "HEAD OF FINANCE AND BUSINESS REPORTING", cell(sheet, "C23").value
    end

    test "the LISTS sheet the formulas depend on survives" do
      workbook = RubyXL::Parser.parse_buffer(InternationalXlsx.new.generate(payment))

      assert_equal %w[FORM LISTS], workbook.worksheets.map(&:sheet_name)
      assert_equal "FINANCE TEAM CO-ORDINATOR or FINANCE ANALYST",
                   workbook["LISTS"].sheet_data[8][0].value
    end

    test "formula-triggering free text is neutralised" do
      sheet = parsed(InternationalXlsx.new.generate(
        payment(payee_name: "=cmd|'/c calc'!A1", description: "+SUM(A1:A9)")
      ))

      assert_equal "'=cmd|'/c calc'!A1", cell(sheet, "C8").value
      assert_equal "'+SUM(A1:A9)", cell(sheet, "C9").value
    end

    # --- Refusals: each a form EUSA could not act on -------------------------

    test "refuses a blank cost centre" do
      # Defaulting to F40 would book a termtime payment to the Fringe.
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

      assert_equal "First Supplier", cell(first, "C8").value
      assert_equal "Second Supplier", cell(second, "C8").value
    end
  end
end
