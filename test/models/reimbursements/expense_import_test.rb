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

    def build_import(data, input_type: :paste, existing_expenses: [], budgets: [ @budget ])
      ExpenseImport.new(data, input_type: input_type, financial_year: @year,
                              cost_centre: @cost_centre, budgets: budgets,
                              people: [ @payee ], existing_expenses: existing_expenses)
    end

    # A show's line after the area rename: the area holds the grouping and the
    # budget is bare.
    def marketing_in(show)
      area = create_reimbursements_area(name: show, cost_centre: @cost_centre,
                                        financial_year: @year)
      create_reimbursements_budget(name: "Marketing", area: area, cost_centre: @cost_centre,
                                   financial_year: @year)
    end

    # --- Budgets whose names the area rename changed -------------------------
    # Settled claims come through here, so a budget resolved to the wrong show
    # is real money on the wrong line with nothing on screen. The rename made
    # same-named lines in different areas normal, and index_by kept the last.

    test "a sheet still writing the prefix finds the renamed line" do
      marketing = marketing_in("Cogito")

      import = build_import(tsv(row(budget: "Cogito: Marketing")), budgets: [ marketing ])

      assert_equal :create, import.entries.sole.bucket
      assert_equal marketing.record_id, import.entries.sole.budget.record_id
    end

    test "a bare name two shows both answer to blocks the row" do
      budgets = [ marketing_in("Cogito"), marketing_in("Improverts") ]

      import = build_import(tsv(row(budget: "Marketing")), budgets: budgets)

      assert_not import.valid?
      error = import.entries.sole.error
      assert_match(/matches more than one budget/, error)
      assert_match(/in Cogito/, error)
      assert_match(/in Improverts/, error)
    end

    # "Area: Line" resolves a candidate that has an area and nothing else, so
    # offering it for two loose budgets would name a fix that cannot be made.
    test "the ambiguity message offers a fix that exists" do
      budgets = [ marketing_in("Cogito"), marketing_in("Improverts") ]
      loose = [ @budget, create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                                      financial_year: @year) ]

      areas = build_import(tsv(row(budget: "Marketing")), budgets: budgets)
      assert_match(/Write the one you mean as "Cogito: Marketing"/, areas.entries.sole.error)

      none = build_import(tsv(row(budget: "Props")), budgets: loose)
      assert_match(/Rename one of them/, none.entries.sole.error)
      assert_no_match(/Area: Line/, none.entries.sole.error)
    end

    # Two areas of one name is the lenient-scoping shape, and "Cogito: Marketing"
    # then resolves nothing — so the message must not name it as the fix, and
    # the candidates must be told apart by something.
    test "the fix is not a spelling that reproduces the same block" do
      here = marketing_in("Cogito")
      stale = create_reimbursements_budget(name: "Marketing", area: Area.create!(name: "Cogito"))

      import = build_import(tsv(row(budget: "Marketing")), budgets: [ here, stale ])

      error = import.entries.sole.error
      assert_no_match(/Write the one you mean/, error)
      assert_match(/Rename one of them/, error)
      assert_match(/Fringe 2027/, error)
      assert_match(/no financial year or cost centre/, error)
    end

    test "naming the area with the line resolves it" do
      cogito = marketing_in("Cogito")

      import = build_import(tsv(row(budget: "Cogito: Marketing")),
                            budgets: [ cogito, marketing_in("Improverts") ])

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal cogito.record_id, import.entries.sole.budget.record_id
    end

    # --- A sheet finance actually has --------------------------------------
    #
    # Every other test here builds its sheet from TSV_HEADERS, which is the one
    # input the column matcher cannot get wrong. These use the headings a real
    # spreadsheet carries, which is where it did.

    REAL_HEADERS = "Claim ID\tStatus\tPayee email\tBudget\tAmount\t" \
                   "Payment reference\tDescription\tPayee name\tSort code\t" \
                   "Account number\tNotes".freeze

    def real_sheet(*rows) = ([ REAL_HEADERS ] + rows).join("\n")

    def real_row(id, amount: "120.00", payment_reference: "PROPS ALICE", account: "66374958")
      [ id, Status::PAID, "alice@example.com", "Props", amount,
        payment_reference, "Fake blood #{id}", "Stage Supplies Ltd", "08-99-99",
        account, "Petty cash" ].join("\t")
    end

    # The BACS reference repeats across a payee's claims by design, so reading
    # it as the dedupe key either blocks the sheet naming a column the operator
    # never mapped, or buckets a later genuinely-different claim as already
    # imported and drops it.
    test "the dedupe key comes from the sheet's own id column, never Payment reference" do
      import = build_import(real_sheet(real_row("2019-014"), real_row("2019-015")))

      assert import.valid?, import.entries.map(&:error).compact.to_sentence
      assert_equal %w[2019-014 2019-015], import.creates.map { |attrs| attrs[:import_key] }
    end

    # A supplier's account number parses as an Integer, isn't taken and isn't
    # duplicated, so nothing downstream catches it — and Expense's before_create
    # then numbers every later claim in the portal from 66,374,959.
    test "an Account number column is never read as the expense number" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert import.valid?
      assert_not import.creates.sole.key?(:auto_number)
      assert_equal "66374958", import.creates.sole[:account_number_override]
    end

    test "a Notes column is never read as the expense number" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert_not import.creates.sole.key?(:auto_number)
    end

    # Keyword tuning can only ever be nearly right, so the preview states what
    # it read. This is the reader for it.
    test "the import reports which column it read for each field" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert_equal "Claim ID", import.column_mapping.fetch("Reference")
      assert_equal "Payment reference", import.column_mapping.fetch("Payment reference")
      assert_equal "Account number", import.column_mapping.fetch("Account number")
      assert_nil import.column_mapping.fetch("Expense number")
    end

    # "Total amount excl VAT" reads as both the gross and the net — a plausible
    # heading, and exactly the case where picking one silently charges the wrong
    # figure to a budget.
    test "two fields resolving to one column block the import, naming both" do
      headers = "Reference\tStatus\tPayee email\tBudget\tTotal amount excl VAT"
      import = build_import([ headers,
                              "R1\tPaid\talice@example.com\tProps\t120" ].join("\n"))

      assert_not import.valid?
      assert_match(/Total amount excl VAT/, import.errors.to_sentence)
      assert_match(/Amount and Amount excl VAT/, import.errors.to_sentence)
    end

    test "a sheet whose columns each read as one field is not reported ambiguous" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert import.valid?, import.errors.to_sentence
    end

    # --- The unique index folds case; the pre-flight read has to too ---------

    test "a reference differing only in case is already imported, not a second create" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               import_key: "OLD-1")

      import = build_import(tsv(row(reference: "old-1")), existing_expenses: [ existing ])

      assert import.valid?
      assert_equal :already_imported, import.entries.sole.bucket
      assert_empty import.creates
    end

    test "two references differing only in case block the sheet" do
      import = build_import(tsv(row(reference: "OLD-1"), row(reference: "old-1")))

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
    end

    # --- A reference too long for its column ---------------------------------

    test "a reference longer than the column blocks the import instead of 500ing" do
      import = build_import(tsv(row(reference: "R" * 300)))

      assert_not import.valid?
      assert_match(/too long/i, import.entries.sole.error)
    end

    # --- Escaping belongs to the round trip, not to the operator's paste ------

    test "a backslash typed in a pasted cell is stored verbatim" do
      import = build_import(tsv(row(description: "Receipt at C:\\temp\\report.pdf")))

      assert import.valid?
      assert_equal "Receipt at C:\\temp\\report.pdf", import.creates.sole[:description]
    end

    # --- What happens to a claim imported live -------------------------------

    test "claims imported at a live status are counted, so the preview can warn" do
      import = build_import(tsv(row(reference: "OLD-1", status: Status::APPROVED),
                                row(reference: "OLD-2", status: Status::PENDING),
                                row(reference: "OLD-3", status: Status::PAID)))

      assert_equal %w[OLD-1 OLD-2], import.live_entries.map { |e| e.row[:reference] }
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
      import = build_import(tsv(row(description: "Blood\\tand\\nglitter")),
                            input_type: :canonical_tsv)
      assert_equal "Blood\tand\nglitter", import.entries.sole.row[:description]

      again = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal "Blood\tand\nglitter", again.entries.sole.row[:description]
      assert again.valid?
    end

    # The same bytes read as the operator's own paste, where a backslash is a
    # backslash. Only the preview's hidden field is this class's own output.
    test "the same escape sequence in a pasted cell is left alone" do
      import = build_import(tsv(row(description: "Blood\\tand glitter")))

      assert_equal "Blood\\tand glitter", import.entries.sole.row[:description]
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
