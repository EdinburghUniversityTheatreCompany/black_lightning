require "test_helper"

module Reimbursements
  # The committee's budget spreadsheet, read into buckets the operator confirms
  # before anything is written.
  class BudgetImportTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @year = FinancialYear.create!(label: "Fringe 2027")
      @cost_centre = CostCentre.default ||
                     create_reimbursements_cost_centre(key: "fringe", name: "Bedlam Fringe",
                                                       eusa_code: "F40",
                                                       receive_mailbox: "in@x.co",
                                                       send_mailbox: "out@x.co")
    end

    HEADERS = "Budget\tNominal code\tType\tAmount\tOwner emails\tNotes".freeze

    def tsv(*rows)
      ([ HEADERS ] + rows).join("\n")
    end

    def build_import(data, input_type: :paste, existing_budgets: [], people: [])
      BudgetImport.new(data, input_type: input_type, financial_year: @year,
                             cost_centre: @cost_centre, existing_budgets: existing_budgets,
                             people: people)
    end

    # A "Props" line inside an area BOB owns, plus Alice, who the committee's
    # sheet names. +own_owners+ puts Alice on the budget's OWN rows too — the
    # state DatabaseStore#sync_budget_owners! would leave behind.
    def props_in_area_owned_by_bob(own_owners: false)
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito", financial_year: @year,
                                        cost_centre: @cost_centre)
      area.sync_owner_ids!([ bob.id ])
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000, area: area,
                                            owners: own_owners ? [ alice ] : [],
                                            financial_year: @year, cost_centre: @cost_centre)
      [ budget, alice, bob ]
    end

    # --- Adoption of unplaced budgets ---------------------------------------
    # The lenient cost-centre scoping that lets a legacy line with no centre be
    # matched at all also puts it in EVERY centre's list. Without adoption two
    # committees' sheets take turns revising one shared row, each overwriting
    # the other's forecast, and neither centre ever gets a line of its own.

    test "a matched budget with no cost centre is adopted into this import's centre" do
      unplaced = create_reimbursements_budget(name: "Venue hire", initial_budget: 1000)

      import = build_import(tsv("Venue hire\t4000\tExpense\t1200\t\t"),
                            existing_budgets: [ unplaced ])

      assert_equal [ { budget_id: unplaced.record_id, cost_centre: @cost_centre } ],
                   import.adoptions
    end

    test "adoption does not depend on the figure having moved" do
      unplaced = create_reimbursements_budget(name: "Venue hire", initial_budget: 1200)

      import = build_import(tsv("Venue hire\t4000\tExpense\t1200\t\t"),
                            existing_budgets: [ unplaced ])

      assert_equal :unchanged, import.entries.sole.bucket
      assert_equal [ unplaced.record_id ], import.adoptions.map { |a| a[:budget_id] }
    end

    test "a budget that already names a cost centre is never re-homed" do
      placed = create_reimbursements_budget(name: "Venue hire", initial_budget: 1000,
                                            cost_centre: @cost_centre)

      import = build_import(tsv("Venue hire\t4000\tExpense\t1200\t\t"),
                            existing_budgets: [ placed ])

      assert_empty import.adoptions
    end

    # --- Parsing -------------------------------------------------------------

    test "reads a pasted sheet into rows" do
      import = build_import(tsv("Props\t4000\tExpense\t1200\t\tFake blood etc"))

      assert_predicate import, :valid?
      entry = import.entries.sole
      assert_equal "Props", entry.row[:name]
      assert_equal "4000", entry.row[:nominal_code]
      assert_equal "Expense", entry.row[:budget_type]
      assert_equal BigDecimal("1200"), entry.row[:amount]
      assert_equal "Fake blood etc", entry.row[:notes]
    end

    test "reads an uploaded xlsx" do
      file = xlsx_fixture([ HEADERS.split("\t"), [ "Props", "4000", "Expense", "1200", "", "" ] ])

      import = build_import(file, input_type: :xlsx)

      assert_predicate import, :valid?
      assert_equal "Props", import.entries.sole.row[:name]
      assert_equal BigDecimal("1200"), import.entries.sole.row[:amount]
    end

    test "reads money the way the rest of the portal does" do
      import = build_import(tsv("Props\t4000\tExpense\t£1,200.50\t\t",
                                "Venue\t4100\tExpense\t12,50\t\t"))

      assert_equal [ BigDecimal("1200.50"), BigDecimal("12.50") ], import.entries.map { |e| e.row[:amount] }
    end

    test "defaults the type to Expense and recognises Income" do
      import = build_import(tsv("Props\t4000\t\t100\t\t", "Ticket income\t1000\tincome\t8000\t\t"))

      assert_equal %w[Expense Income], import.entries.map { |e| e.row[:budget_type] }
    end

    test "an empty paste is not an import" do
      import = build_import(tsv)

      assert_not_predicate import, :valid?
      assert_empty import.entries
    end

    test "a sheet with no recognisable budget-name column is rejected as a whole" do
      import = build_import("Thing\tCost\nProps\t1200")

      assert_not_predicate import, :valid?
      assert_match(/budget name/i, import.errors.to_sentence)
    end

    # --- Buckets -------------------------------------------------------------

    test "a line that matches nothing is a create" do
      import = build_import(tsv("Props\t4000\tExpense\t1200\t\t"))

      assert_equal [ :create ], import.entries.map(&:bucket)
      assert_equal 1, import.creates.size
      assert_equal "Props", import.creates.first[:name]
      assert_equal @year, import.creates.first[:financial_year]
      assert_equal @cost_centre, import.creates.first[:cost_centre]
    end

    test "a line matching an existing budget with a new amount is a revision" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000)

      import = build_import(tsv("props\t4000\tExpense\t1200\t\t"), existing_budgets: [ budget ])

      assert_equal [ :revise ], import.entries.map(&:bucket)
      assert_equal [ { budget_id: budget.record_id, amount: BigDecimal("1200") } ], import.revisions
      # The agreed figure is never rewritten by a re-import: variance is
      # measured against it.
      assert_empty import.creates
    end

    test "a line matching an existing budget at the same figure is unchanged" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1200)

      import = build_import(tsv("Props\t4000\tExpense\t1200\t\t"), existing_budgets: [ budget ])

      assert_equal [ :unchanged ], import.entries.map(&:bucket)
      assert_empty import.revisions
    end

    test "a revision compares against the latest forecast, not the initial figure" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000)
      budget.forecasts.create!(amount: 1200, date: Date.new(2027, 1, 1))

      import = build_import(tsv("Props\t4000\tExpense\t1200\t\t"), existing_budgets: [ budget ])

      assert_equal [ :unchanged ], import.entries.map(&:bucket)
    end

    test "a line with no amount is left alone rather than zeroed" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000)

      import = build_import(tsv("Props\t4000\tExpense\t\t\t"), existing_budgets: [ budget ])

      assert_equal [ :unchanged ], import.entries.map(&:bucket)
      assert_empty import.revisions
    end

    test "budgets in the year but absent from the sheet are reported, never deleted" do
      budget = create_reimbursements_budget(name: "Retired line")

      import = build_import(tsv("Props\t4000\tExpense\t1200\t\t"), existing_budgets: [ budget ])

      assert_equal [ budget ], import.absent_budgets
      assert_predicate import, :valid?
    end

    # --- Invalid rows block the whole import ---------------------------------

    test "an unreadable amount blocks the import" do
      import = build_import(tsv("Props\t4000\tExpense\t1200\t\t",
                                "Venue\t4100\tExpense\tabout a grand\t\t"))

      assert_not_predicate import, :valid?
      assert_equal %i[create invalid], import.entries.map(&:bucket)
      assert_match(/about a grand/, import.entries.last.error)
    end

    test "a row with no name blocks the import" do
      import = build_import(tsv("\t4000\tExpense\t1200\t\t"))

      assert_not_predicate import, :valid?
      assert_match(/name/i, import.entries.sole.error)
    end

    test "an unknown budget type blocks the import" do
      import = build_import(tsv("Props\t4000\tCapital\t1200\t\t"))

      assert_not_predicate import, :valid?
      assert_match(/Capital/, import.entries.sole.error)
    end

    test "the same name twice in one sheet blocks the import, flagging both" do
      import = build_import(tsv("Props\t4000\tExpense\t100\t\t", "props\t4000\tExpense\t200\t\t"))

      assert_not_predicate import, :valid?
      assert_equal %i[invalid invalid], import.entries.map(&:bucket)
      assert import.entries.all? { |e| e.error.match?(/twice|more than once/i) }
    end

    test "a blank nominal code is allowed but counted" do
      import = build_import(tsv("Props\t\tExpense\t1200\t\t"))

      assert_predicate import, :valid?
      assert_equal 1, import.missing_nominal_codes.size
    end

    # --- Owners --------------------------------------------------------------

    test "owner emails link to people" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")

      import = build_import(tsv("Props\t4000\tExpense\t100\tALICE@example.com; bob@example.com\t"),
                            people: [ alice, bob ])

      assert_equal [ alice.id, bob.id ].sort, import.creates.first[:owner_ids].map(&:to_i).sort
    end

    test "an unrecognised owner email warns but never blocks" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")

      import = build_import(tsv("Props\t4000\tExpense\t100\talice@example.com, gone@example.com\t"),
                            people: [ alice ])

      # A stale committee email must not stop thirty budget lines landing; a
      # missing owner shows up later as an unendorsed claim, which is visible.
      assert_predicate import, :valid?
      assert_equal [ "gone@example.com" ], import.unknown_owner_emails
      assert_equal [ alice.id.to_s ], import.creates.first[:owner_ids]
    end

    test "a revision keeps the sheet's owners for the matched budget" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000)

      import = build_import(tsv("Props\t4000\tExpense\t1200\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice ])

      assert_equal [ { budget_id: budget.record_id, owner_ids: [ alice.id.to_s ] } ], import.owner_syncs
    end

    # DatabaseStore#sync_budget_owners! writes the budget's OWN rows, so the
    # "has this already been synced?" comparison has to read the same rows.
    # Comparing the area-resolved Budget#owner_ids can never converge: the
    # sheet's owner is written to own_owners, #owners keeps returning the
    # area's, and every later re-import reports the identical sync again.
    test "a matched budget in an area is compared against its OWN owner rows" do
      budget, alice, bob = props_in_area_owned_by_bob(own_owners: true)

      import = build_import(tsv("Props\t4000\tExpense\t1000\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice, bob ])

      assert_empty import.owner_syncs,
                   "Alice is already the budget's own owner — there is nothing to write"
    end

    test "an owner sync inside an area converges: a re-import reports it once" do
      budget, alice, bob = props_in_area_owned_by_bob
      sheet = tsv("Props\t4000\tExpense\t1000\talice@example.com\t")

      first = build_import(sheet, existing_budgets: [ budget ], people: [ alice, bob ])
      assert_equal [ { budget_id: budget.record_id, owner_ids: [ alice.id.to_s ] } ],
                   first.owner_syncs

      DatabaseStore.new.sync_budget_owners!(budget.record_id, [ alice.id.to_s ])

      second = build_import(sheet, existing_budgets: [ budget.reload ], people: [ alice, bob ])
      assert_empty second.owner_syncs, "the same sync must not be reported for ever"
    end

    # --- Round-tripping an upload through the preview -------------------------

    test "to_tsv re-parses to the same rows" do
      original = build_import(tsv("Props\t4000\tExpense\t£1,200\talice@example.com\tSome notes"))

      round_tripped = build_import(original.to_tsv, input_type: :canonical_tsv)

      assert_equal original.entries.map(&:row), round_tripped.entries.map(&:row)
    end

    test "to_tsv survives a tab or newline typed into an uploaded cell" do
      # An xlsx cell really can contain a tab or a line break, and the preview
      # carries the sheet on as TSV in a hidden field — so without escaping,
      # one stray tab in a note shifts every later column when apply re-parses.
      file = xlsx_fixture([ HEADERS.split("\t"),
                            [ "Props", "4000", "Expense", "100", "", "one\ttwo\nthree" ] ])
      import = build_import(file, input_type: :xlsx)

      round_tripped = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal import.entries.map(&:row), round_tripped.entries.map(&:row)
      assert_equal "one\ttwo\nthree", round_tripped.entries.sole.row[:notes]
      assert_equal 1, round_tripped.entries.size
    end

    # A pasted sheet can't hold either character — parse_tsv splits on them —
    # so they only ever arrive from an xlsx cell, already escaped, and must
    # leave escaped or one stray tab shifts every later column on the re-parse.
    test "an escaped cell coming back from the preview is unescaped once" do
      import = build_import(tsv("Costume\\nrepairs\t4000\tExpense\t100\t\tone\\ttwo"),
                            input_type: :canonical_tsv)

      assert_equal "Costume\nrepairs", import.entries.sole.row[:name]
      assert_equal "one\ttwo", import.entries.sole.row[:notes]

      again = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal "Costume\nrepairs", again.entries.sole.row[:name]
      assert_equal "one\ttwo", again.entries.sole.row[:notes]
    end

    # The same bytes read as the operator's own paste, where a backslash is a
    # backslash. Only the preview's hidden field is this class's own output.
    test "a backslash in the operator's own paste is left alone" do
      import = build_import(tsv("Costume\\next week\t4000\tExpense\t100\t\tC:\\temp\\report.pdf"))

      assert_equal "Costume\\next week", import.entries.sole.row[:name]
      assert_equal "C:\\temp\\report.pdf", import.entries.sole.row[:notes]
    end

    # The name is what an existing budget is MATCHED on, so rewriting it turns a
    # revision into a create — a second line beside the one it meant to update.
    test "a pasted backslash name still matches the budget it names" do
      existing = create_reimbursements_budget(name: "Costume\\next week", initial_budget: 1000,
                                              cost_centre: @cost_centre, financial_year: @year)

      import = build_import(tsv("Costume\\next week\t4000\tExpense\t1200\t\t"),
                            existing_budgets: [ existing ])

      assert_equal :revise, import.entries.sole.bucket
    end

    private

    def xlsx_fixture(rows)
      require "caxlsx"
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Budget") do |sheet|
        rows.each { |row| sheet.add_row row }
      end
      file = Tempfile.new([ "budget", ".xlsx" ])
      file.binmode
      file.write(package.to_stream.read)
      file.flush
      file
    end
  end
end
