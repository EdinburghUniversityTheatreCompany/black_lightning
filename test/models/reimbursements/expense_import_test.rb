require "test_helper"
require_relative "../../support/expense_import_sheet_helpers"

module Reimbursements
  # Finance's historical-claims spreadsheet, read into buckets the operator
  # confirms before anything is written.
  class ExpenseImportTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers
    include ExpenseImportSheetHelpers

    setup do
      @year = FinancialYear.create!(label: "Fringe 2027")
      @cost_centre = CostCentre.default
      @payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
      @budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                             financial_year: @year)
    end

    def row(**) = expense_import_row(**)

    def tsv(*) = expense_import_sheet(*)

    def build_import(data, input_type: :paste, existing_expenses: [], budgets: [ @budget ],
                     people: [ @payee ])
      ExpenseImport.new(data, input_type: input_type, financial_year: @year,
                              cost_centre: @cost_centre, budgets: budgets,
                              people: people, existing_expenses: existing_expenses)
    end

    # A show's line after the area rename: the area holds the grouping, the budget is bare.
    def marketing_in(show)
      area = create_reimbursements_area(name: show, cost_centre: @cost_centre,
                                        financial_year: @year)
      create_reimbursements_budget(name: "Marketing", area: area, cost_centre: @cost_centre,
                                   financial_year: @year)
    end

    # --- Budgets whose names the area rename changed -------------------------

    test "a bare name two shows both answer to blocks the row" do
      budgets = [ marketing_in("Cogito"), marketing_in("Improverts") ]

      import = build_import(tsv(row(budget: "Marketing")), budgets: budgets)

      assert_not import.valid?
      error = import.entries.sole.error
      assert_match(/matches more than one budget/, error)
      assert_match(/in Cogito/, error)
      assert_match(/in Improverts/, error)
      assert_match(/Write the one you mean as "Cogito: Marketing"/, error)
    end

    test "two loose budgets of one name are told to rename one" do
      loose = [ @budget, create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                                      financial_year: @year) ]

      import = build_import(tsv(row(budget: "Props")), budgets: loose)

      assert_match(/Rename one of them/, import.entries.sole.error)
    end

    # Two areas of one name: "Cogito: Marketing" resolves nothing, so it must not be
    # offered as the fix.
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
    # Every other test builds its sheet from TSV_HEADERS, which the column matcher cannot
    # get wrong. These use the headings a real spreadsheet carries, where it did.

    REAL_HEADERS = "Claim ID\tStatus\tPayee email\tBudget\tAmount\t" \
                   "Payment reference\tDescription\tPayee name\tSort code\t" \
                   "Account number\tNotes".freeze

    def real_sheet(*rows) = ([ REAL_HEADERS ] + rows).join("\n")

    def real_row(id, amount: "120.00", payment_reference: "PROPS ALICE", account: "66374958")
      [ id, Status::PAID, "alice@example.com", "Props", amount,
        payment_reference, "Fake blood #{id}", "Stage Supplies Ltd", "08-99-99",
        account, "Petty cash" ].join("\t")
    end

    # The BACS reference repeats across a payee's claims, so as the dedupe key it would
    # bucket a later, different claim as already imported and drop it.
    test "the dedupe key comes from the sheet's own id column, never Payment reference" do
      import = build_import(real_sheet(real_row("2019-014"), real_row("2019-015")))

      assert import.valid?, import.entries.map(&:error).compact.to_sentence
      assert_equal %w[2019-014 2019-015], import.creates.map { |attrs| attrs[:import_key] }
    end

    # A supplier's account number parses as an Integer and is neither taken nor
    # duplicated, so nothing downstream catches it: Expense's before_create would number
    # every later claim in the portal from 66,374,959.
    test "an Account number column is never read as the expense number" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert import.valid?
      assert_not import.creates.sole.key?(:auto_number)
      assert_equal "66374958", import.creates.sole[:account_number_override]
    end

    test "the import reports which column it read for each field" do
      import = build_import(real_sheet(real_row("2019-014")))

      assert_equal "Claim ID", import.column_mapping.fetch("ID")
      assert_equal "Payment reference", import.column_mapping.fetch("Payment reference")
      assert_equal "Account number", import.column_mapping.fetch("Account number")
      assert_nil import.column_mapping.fetch("Expense number")
    end

    # "Total amount excl VAT" reads as both gross and net; picking one would silently
    # charge the wrong figure to a budget.
    test "two fields resolving to one column block the import, naming both" do
      headers = "Reference\tStatus\tPayee email\tBudget\tTotal amount excl VAT"
      import = build_import([ headers,
                              "R1\tPaid\talice@example.com\tProps\t120" ].join("\n"))

      assert_not import.valid?
      assert_match(/Total amount excl VAT/, import.errors.to_sentence)
      assert_match(/Amount and Amount excl VAT/, import.errors.to_sentence)
    end

    # --- IDs and the double-apply guard ---------------------------------------

    test "a reference already on record, in any case, is skipped while the rest import" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               import_key: "OLD-1")

      import = build_import(tsv(row(reference: "old-1"), row(reference: "OLD-2")),
                            existing_expenses: [ existing ])

      assert import.valid?
      assert_equal %i[already_imported create], import.entries.map(&:bucket)
      assert_equal [ "OLD-2" ], import.creates.map { |attrs| attrs[:import_key] }
    end

    test "a row already imported under its expense number is skipped, not blocked by it" do
      existing = create_reimbursements_expense(person: @payee, budget: @budget, receipt: false,
                                               import_key: "OLD-1", auto_number: 417)

      import = build_import(tsv(row(reference: "OLD-1", auto_number: "417")),
                            existing_expenses: [ existing ])

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal :already_imported, import.entries.sole.bucket
    end

    test "two references differing only in case block the sheet" do
      import = build_import(tsv(row(reference: "OLD-1"), row(reference: "old-1")))

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
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

    test "a well-formed line becomes one create with its amounts, payee, budget and year" do
      import = build_import(tsv(row))

      assert import.valid?
      attrs = import.creates.sole
      assert_equal BigDecimal("120"), attrs[:amount]
      assert_equal BigDecimal("100"), attrs[:amount_excl_vat]
      assert_equal Status::PAID, attrs[:status]
      assert_equal @payee.record_id, attrs[:person_record_id]
      assert_equal @budget.record_id, attrs[:budget_record_id]
      assert_equal @year, attrs[:financial_year]
    end

    test "a typed amount is written as a BigDecimal, never the raw string" do
      import = build_import(tsv(row(amount: "£1,200", amount_excl_vat: "£1,000")))

      assert import.valid?
      assert_equal BigDecimal("1200"), import.creates.sole[:amount]
    end

    test "a blank ex-VAT amount falls back to the gross, never to nil" do
      import = build_import(tsv(row(amount_excl_vat: "")))

      assert import.valid?
      assert_equal BigDecimal("120"), import.creates.sole[:amount_excl_vat]
    end

    # --- Mandatory status ----------------------------------------------------

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

    test "a budget name matches case- and space-insensitively" do
      import = build_import(tsv(row(budget: " props ")))

      assert import.valid?
      assert_equal @budget.record_id, import.creates.sole[:budget_record_id]
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

    test "the paid and submitted dates are read into their columns" do
      import = build_import(tsv(row(submitted_on: "2026-05-01", paid_on: "2026-05-13")))

      attrs = import.creates.sole
      assert_equal Date.new(2026, 5, 13), attrs[:payment_confirmed_date]
      assert_equal Date.new(2026, 5, 1), attrs[:submitted_at].to_date
    end

    # --- Rows that block the import --------------------------------------------

    test "a row wrong in any one way blocks the import and says why" do
      {
        { reference: "R" * 300 } => /too long/i,
        { reference: "" } => /\bID\b/,
        { status: "" } => /status/i,
        { status: "Reimbursed" } => /"Reimbursed" isn't a status.*Approved/,
        { payee_email: "nobody@example.com" } => /nobody@example\.com.*People/,
        { payee_email: "", submitter_name: "Nobody Known" } => /isn't anyone on the People screen/,
        { budget: "Lighting" } => /Lighting/,
        { paid_on: "the third of never" } => /never/,
        { description: "" } => /description/i,
        { payment_reference: "" } => /Payment reference/i,
        { payment_reference: "A" * 30 } => /reference/i,
        { amount: "100", amount_excl_vat: "120" } => /excl/i,
        { amount: "-5" } => /positive/i,
        { expense_type: "Petty cash" } => /type/i,
        { auto_number: "four-one-seven" } => /"four-one-seven" isn't an expense number/,
        { status: Status::APPROVED, expense_type: Expense::TYPE_INVOICE } => /payee/i
      }.each do |cells, message|
        import = build_import(tsv(row(**cells)))

        assert_not import.valid?, cells.inspect
        assert_match message, import.entries.sole.error, cells.inspect
      end
    end

    # --- The internal escape hatch -------------------------------------------

    test "an import asks for no receipt, VAT tick or large-amount tick" do
      import = build_import(tsv(row(amount: "5000", amount_excl_vat: "5000")))

      assert import.valid?
    end

    # --- Who the claim belongs to --------------------------------------------

    # A blank cell once matched whichever email-less payee was indexed last (140 claims
    # went to "Fringe Society").
    test "a blank submitter email never matches a payee who has no email" do
      emailless = create_reimbursements_person(name: "Fringe Society", email: nil)

      import = build_import(tsv(row(payee_email: "")), people: [ @payee, emailless ])

      assert_not import.valid?
      assert_nil import.entries.sole.person
      assert_match(/names no submitter/, import.entries.sole.error)
      assert_not import.entries.sole.unknown_submitter
    end

    test "with no email, the submitter is found by name, ignoring case and accents" do
      zoe = create_reimbursements_person(name: "Zoë Producer", email: nil)
      import = build_import(tsv(row(payee_email: "", submitter_name: " zoe  producer ")),
                            people: [ @payee, zoe ])

      assert import.valid?, import.entries.map(&:error).compact.to_sentence
      assert_equal zoe.record_id, import.creates.sole[:person_record_id]
    end

    test "an email, when given, wins over the name" do
      import = build_import(tsv(row(payee_email: "alice@example.com", submitter_name: "Somebody Else")))

      assert import.valid?, import.entries.map(&:error).compact.to_sentence
      assert_equal @payee.record_id, import.entries.sole.person.record_id
    end

    test "a name two payees share blocks the row rather than picking one" do
      twins = Array.new(2) { |i| create_reimbursements_person(name: "Sam Jones", email: "sam#{i}@example.com") }
      import = build_import(tsv(row(payee_email: "", submitter_name: "Sam Jones")), people: twins)

      assert_not import.valid?
      assert_match(/more than one person/, import.entries.sole.error)
      assert_not import.entries.sole.unknown_submitter
    end

    test "a submitter the People screen lacks is flagged, so the preview can offer to register them" do
      import = build_import(tsv(row(payee_email: "nobody@example.com")))

      assert import.entries.sole.unknown_submitter
    end

    test "the old Reference and Payee email headings still read" do
      legacy = tsv(row).sub(/\AID\t/, "Reference\t").sub("Submitter email\t", "Payee email\t")
      import = build_import(legacy)

      assert import.valid?, import.errors.to_sentence
      assert_equal "Reference", import.column_mapping.fetch("ID")
      assert_equal "Payee email", import.column_mapping.fetch("Submitter email")
    end

    # The template's explanation row is words, not a claim: left in, it would block the import.
    test "a sheet still carrying the template's explanation row imports only its real rows" do
      import = build_import(tsv(ExpenseImport::TEMPLATE_HINTS.join("\t"), row))

      assert import.valid?, (import.errors + import.entries.map(&:error)).compact.to_sentence
      assert_equal [ "OLD-1" ], import.entries.map { |entry| entry.row[:reference] }
    end

    # Nobody types the full "From EUSA (utility, staff cost, etc)" into a cell.
    test "From EUSA is importable, bare or in full" do
      [ "from eusa", Expense::TYPE_FROM_EUSA ].each do |typed|
        import = build_import(tsv(row(expense_type: typed)))

        assert import.valid?, typed
        assert_equal Expense::TYPE_FROM_EUSA, import.creates.sole[:expense_type], typed
      end
    end

    # --- Invoices and the payee trio ------------------------------------------

    test "a settled Invoice imports without the payee trio: no money will move again" do
      import = build_import(tsv(row(status: Status::PAID, expense_type: Expense::TYPE_INVOICE)))

      assert import.valid?
    end

    test "the payee trio from the sheet satisfies an Approved Invoice" do
      import = build_import(tsv(row(status: Status::APPROVED, expense_type: Expense::TYPE_INVOICE,
                                    payee_name_override: "Stage Supplies Ltd",
                                    sort_code_override: "08-99-99",
                                    account_number_override: "66374958")))

      assert import.valid?
      assert_equal "Stage Supplies Ltd", import.creates.sole[:payee_name_override]
    end

    # --- The hidden field the wizard carries ----------------------------------

    # A pasted sheet can't hold a tab or newline (parse_tsv splits on them), so they only
    # arrive from an xlsx cell, already escaped, and must leave escaped or a stray tab
    # shifts every later column on the re-parse.
    test "a cell holding a tab or a newline survives the round trip into apply" do
      import = build_import(tsv(row(description: "Blood\\tand\\nglitter")),
                            input_type: :canonical_tsv)
      assert_equal "Blood\tand\nglitter", import.entries.sole.row[:description]

      again = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal "Blood\tand\nglitter", again.entries.sole.row[:description]
      assert again.valid?
    end

    test "an unreadable amount is carried on verbatim, through the round trip too" do
      first = build_import(tsv(row(amount: "12\\ quid")))

      again = build_import(first.to_tsv, input_type: :canonical_tsv)

      assert_equal "12\\ quid", again.entries.sole.row[:raw_amount]
      assert_equal first.to_tsv, again.to_tsv
    end

    test "a wholly blank line is ignored rather than reported as a nameless claim" do
      import = build_import(tsv(row, "\t\t\t\t\t\t\t\t\t\t\t\t\t\t"))

      assert_equal 1, import.entries.size
      assert import.valid?
    end
  end
end
