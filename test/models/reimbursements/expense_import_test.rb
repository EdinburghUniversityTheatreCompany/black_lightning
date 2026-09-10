require "test_helper"

module Reimbursements
  # Finance's historical-claims spreadsheet, read into buckets the operator
  # confirms before anything is written.
  class ExpenseImportTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    HEADERS = ExpenseImport::TSV_HEADERS.join("\t").freeze

    setup do
      @year = FinancialYear.create!(label: "Fringe 2027")
      @cost_centre = CostCentre.default ||
                     create_reimbursements_cost_centre(key: "fringe", name: "Bedlam Fringe",
                                                       eusa_code: "F40")
      @payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
      @budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                             financial_year: @year)
    end

    # One well-formed line, with the fields a test cares about overridden.
    def row(**overrides)
      cells = { reference: "OLD-1", status: Status::PAID, payee_email: "alice@example.com",
                budget: "Props", amount: "120.00", amount_excl_vat: "100.00",
                description: "Fake blood", payment_reference: "PROPS ALICE",
                expense_type: "", auto_number: "", submitted_on: "", paid_on: "",
                payee_name_override: "", sort_code_override: "", account_number_override: "" }
        .merge(overrides)
      cells.values_at(:reference, :status, :payee_email, :budget, :amount, :amount_excl_vat,
                      :description, :payment_reference, :expense_type, :auto_number,
                      :submitted_on, :paid_on, :payee_name_override, :sort_code_override,
                      :account_number_override).join("\t")
    end

    def tsv(*rows)
      ([ HEADERS ] + rows).join("\n")
    end

    def build_import(data, input_type: :paste, existing_expenses: [])
      ExpenseImport.new(data, input_type: input_type, financial_year: @year,
                              cost_centre: @cost_centre, budgets: [ @budget ],
                              people: [ @payee ], existing_expenses: existing_expenses)
    end

    # --- The happy path ------------------------------------------------------

    test "a well-formed line becomes one create carrying the parsed amount" do
      import = build_import(tsv(row))

      assert import.valid?
      attrs = import.creates.sole
      assert_equal BigDecimal("120"), attrs[:amount]
      assert_equal BigDecimal("100"), attrs[:amount_excl_vat]
      assert_equal Status::PAID, attrs[:status]
    end

    test "a typed amount is written as a BigDecimal, never the raw string" do
      import = build_import(tsv(row(amount: "£1,200", amount_excl_vat: "£1,000")))

      assert import.valid?
      assert_equal BigDecimal("1200"), import.creates.sole[:amount]
    end

    test "the payee and the budget resolve to their records" do
      import = build_import(tsv(row))

      attrs = import.creates.sole
      assert_equal @payee.record_id, attrs[:person_record_id]
      assert_equal @budget.record_id, attrs[:budget_record_id]
    end

    test "a blank ex-VAT amount falls back to the gross, never to nil" do
      import = build_import(tsv(row(amount_excl_vat: "")))

      assert import.valid?
      assert_equal BigDecimal("120"), import.creates.sole[:amount_excl_vat]
    end

    # --- Mandatory status ----------------------------------------------------

    test "a blank status blocks the import" do
      import = build_import(tsv(row(status: "")))

      assert_not import.valid?
      assert_match(/status/i, import.entries.sole.error)
    end

    test "an unrecognised status blocks the import and lists the ones that work" do
      import = build_import(tsv(row(status: "Reimbursed")))

      assert_not import.valid?
      assert_match(/Reimbursed/, import.entries.sole.error)
      assert_match(/Approved/, import.entries.sole.error)
    end

    test "a missing status column is one problem with the sheet, not a broken line" do
      headers = (ExpenseImport::TSV_HEADERS - [ "Status" ]).join("\t")
      import = build_import([ headers, "OLD-1\talice@example.com\tProps\t120\t100\tBlood\tREF" ].join("\n"))

      assert_not import.valid?
      assert_match(/status/i, import.errors.to_sentence)
    end

    # --- All-or-nothing ------------------------------------------------------

    test "one unreadable amount blocks the whole import and names its row" do
      import = build_import(tsv(row(reference: "OLD-1"), row(reference: "OLD-2", amount: "twelve")))

      assert_not import.valid?
      assert_equal 1, import.entries_in(:invalid).size
      assert_equal "OLD-2", import.entries_in(:invalid).sole.row[:reference]
      assert_match(/twelve/, import.entries_in(:invalid).sole.error)
    end

    test "an unknown payee blocks the import and points at the People screen" do
      import = build_import(tsv(row(payee_email: "nobody@example.com")))

      assert_not import.valid?
      assert_match(/nobody@example\.com/, import.entries.sole.error)
      assert_match(/People/i, import.entries.sole.error)
    end

    test "an unknown budget blocks the import" do
      import = build_import(tsv(row(budget: "Lighting")))

      assert_not import.valid?
      assert_match(/Lighting/, import.entries.sole.error)
    end

    test "a budget name matches case- and space-insensitively" do
      import = build_import(tsv(row(budget: " props ")))

      assert import.valid?
      assert_equal @budget.record_id, import.creates.sole[:budget_record_id]
    end

    # --- Double-apply safety -------------------------------------------------

    test "a reference already imported is reported and skipped, never created twice" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               import_key: "OLD-1")

      import = build_import(tsv(row(reference: "OLD-1")), existing_expenses: [ existing ])

      assert import.valid?
      assert_empty import.creates
      assert_equal :already_imported, import.entries.sole.bucket
    end

    test "the second apply of a whole sheet creates nothing" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               import_key: "OLD-1")

      import = build_import(tsv(row(reference: "OLD-1"), row(reference: "OLD-2")),
                            existing_expenses: [ existing ])

      assert_equal [ "OLD-2" ], import.creates.map { |attrs| attrs[:import_key] }
    end

    test "a blank reference blocks the import: there would be no way to tell a re-apply apart" do
      import = build_import(tsv(row(reference: "")))

      assert_not import.valid?
      assert_match(/reference/i, import.entries.sole.error)
    end

    test "a reference repeated within one sheet blocks the import" do
      import = build_import(tsv(row(reference: "OLD-1"), row(reference: "OLD-1")))

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
    end

    # --- Expense numbers -----------------------------------------------------

    test "an expense number from the sheet is carried through" do
      import = build_import(tsv(row(auto_number: "417")))

      assert_equal 417, import.creates.sole[:auto_number]
    end

    test "a blank expense number leaves the key out, so the store assigns one" do
      import = build_import(tsv(row(auto_number: "")))

      assert_not import.creates.sole.key?(:auto_number)
    end

    test "an expense number already on record blocks the import" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               auto_number: 417, import_key: "SOMETHING-ELSE")

      import = build_import(tsv(row(auto_number: "417")), existing_expenses: [ existing ])

      assert_not import.valid?
      assert_match(/417/, import.entries.sole.error)
    end

    test "an expense number repeated within one sheet blocks the import" do
      import = build_import(tsv(row(reference: "OLD-1", auto_number: "417"),
                                row(reference: "OLD-2", auto_number: "417")))

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
    end

    # --- Dates ---------------------------------------------------------------

    test "a paid date is read into payment_confirmed_date" do
      import = build_import(tsv(row(paid_on: "2026-05-13")))

      assert_equal Date.new(2026, 5, 13), import.creates.sole[:payment_confirmed_date]
    end

    test "a submitted date is read into submitted_at" do
      import = build_import(tsv(row(submitted_on: "2026-05-01")))

      assert_equal Date.new(2026, 5, 1), import.creates.sole[:submitted_at].to_date
    end

    test "an unreadable date blocks the import" do
      import = build_import(tsv(row(paid_on: "the third of never")))

      assert_not import.valid?
      assert_match(/never/, import.entries.sole.error)
    end

    # --- ExpenseForm's rules are the import's rules ---------------------------

    test "a blank description blocks the import, as it blocks a submission" do
      import = build_import(tsv(row(description: "")))

      assert_not import.valid?
      assert_match(/description/i, import.entries.sole.error)
    end

    test "an ex-VAT amount above the gross blocks the import" do
      import = build_import(tsv(row(amount: "100", amount_excl_vat: "120")))

      assert_not import.valid?
      assert_match(/excl/i, import.entries.sole.error)
    end

    test "a negative amount blocks the import" do
      import = build_import(tsv(row(amount: "-5")))

      assert_not import.valid?
      assert_match(/positive/i, import.entries.sole.error)
    end

    test "an over-long payment reference blocks the import" do
      import = build_import(tsv(row(payment_reference: "A" * 30)))

      assert_not import.valid?
      assert_match(/reference/i, import.entries.sole.error)
    end

    # --- The internal escape hatch -------------------------------------------

    test "no receipt is required: an imported claim has none to attach" do
      import = build_import(tsv(row))

      assert import.valid?
    end

    test "the VAT soft block never fires: there is no one to tick a box" do
      import = build_import(tsv(row(amount: "120", amount_excl_vat: "120")))

      assert import.valid?
    end

    test "the large-amount soft block never fires" do
      import = build_import(tsv(row(amount: "5000", amount_excl_vat: "5000")))

      assert import.valid?
    end

    test "From EUSA is importable, being a type only the portal's own code writes" do
      import = build_import(tsv(row(expense_type: Expense::TYPE_FROM_EUSA)))

      assert import.valid?
      assert_equal Expense::TYPE_FROM_EUSA, import.creates.sole[:expense_type]
    end

    test "an unrecognised type blocks the import" do
      import = build_import(tsv(row(expense_type: "Petty cash")))

      assert_not import.valid?
    end

    # --- Invoices and the payee trio ------------------------------------------

    test "a settled Invoice imports without the payee trio: no money will move again" do
      import = build_import(tsv(row(status: Status::PAID, expense_type: Expense::TYPE_INVOICE)))

      assert import.valid?
    end

    test "an Approved Invoice still needs the payee trio, because it is about to be paid" do
      import = build_import(tsv(row(status: Status::APPROVED, expense_type: Expense::TYPE_INVOICE)))

      assert_not import.valid?
      assert_match(/payee/i, import.entries.sole.error)
    end

    test "the payee trio from the sheet satisfies an Approved Invoice" do
      import = build_import(tsv(row(status: Status::APPROVED, expense_type: Expense::TYPE_INVOICE,
                                    payee_name_override: "Stage Supplies Ltd",
                                    sort_code_override: "08-99-99",
                                    account_number_override: "66374958")))

      assert import.valid?
      assert_equal "Stage Supplies Ltd", import.creates.sole[:payee_name_override]
    end

    # --- The destination ------------------------------------------------------

    test "every created claim is stamped with the year being imported into" do
      import = build_import(tsv(row))

      assert_equal @year, import.creates.sole[:financial_year]
    end

    test "a budget in another cost centre is not matchable" do
      other = create_second_reimbursements_cost_centre
      elsewhere = create_reimbursements_budget(name: "Lighting", cost_centre: other,
                                               financial_year: @year)
      import = ExpenseImport.new(tsv(row(budget: "Lighting")), input_type: :paste,
                                 financial_year: @year, cost_centre: @cost_centre,
                                 budgets: [ @budget ], people: [ @payee ], existing_expenses: [])

      assert_not import.valid?
      assert_not_nil elsewhere
    end

    # --- The hidden field the wizard carries ----------------------------------

    # A pasted sheet can't hold either character — parse_tsv splits on them —
    # so they only ever arrive from an xlsx cell, already escaped, and must
    # leave escaped or one stray tab shifts every later column on the re-parse.
    test "a cell holding a tab or a newline survives the round trip into apply" do
      import = build_import(tsv(row(description: "Blood\\tand\\nglitter")))
      assert_equal "Blood\tand\nglitter", import.entries.sole.row[:description]

      again = build_import(import.to_tsv)

      assert_equal "Blood\tand\nglitter", again.entries.sole.row[:description]
      assert again.valid?
    end

    test "an unreadable amount is carried on verbatim so the operator can see it" do
      import = build_import(tsv(row(amount: "twelve pounds")))

      assert_match(/twelve pounds/, import.to_tsv)
    end

    test "a wholly blank line is ignored rather than reported as a nameless claim" do
      import = build_import(tsv(row, "\t\t\t\t\t\t\t\t\t\t\t\t\t\t"))

      assert_equal 1, import.entries.size
      assert import.valid?
    end
  end
end
