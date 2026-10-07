require "test_helper"

module Reimbursements
  # The committee's budget spreadsheet, read into buckets the operator confirms
  # before anything is written.
  class BudgetImportTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @year = FinancialYear.create!(label: "Fringe 2027")
      @cost_centre = CostCentre.default
    end

    # Derived, never retyped: see ReimbursementsTestHelpers#budget_import_sheet.
    HEADERS = ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t").freeze

    alias tsv budget_import_sheet

    # The same padding for an xlsx row, which is an Array, not a String.
    def xlsx_sheet(*rows)
      [ HEADERS.split("\t") ] + rows.map { |row| [ "", "" ] + row }
    end

    test "the canonical headings say which column is a name and which is money" do
      assert_equal [ "Area", "Area total", "Budget name", "Nominal code", "Type",
                     "Budget amount", "Owner emails", "Notes" ], BudgetImport::TSV_HEADERS
    end

    # #to_tsv writes these and apply re-parses them.
    test "every canonical heading is read back as its own field" do
      import = build_import(tsv("Props\t432320\tExpense\t400\t\t"))

      BudgetImport::TSV_HEADERS.each do |label|
        assert_equal label, import.column_mapping.fetch(label), "#{label} was not read as itself"
      end
    end

    test "a sheet still carrying the template's explanation row imports only its real rows" do
      hints = BudgetImport::TEMPLATE_HINTS.join("\t")
      import = build_import([ HEADERS, hints, "\t\tProps\t432320\tExpense\t400\t\t" ].join("\n"))

      assert import.valid?, import.errors.to_sentence
      assert_equal [ "Props" ], import.entries.map { |entry| entry.row[:name] }
    end

    test "a sheet with the old headings still reads each column as the same field" do
      import = build_import("Area\tArea Budget\tBudget\tNominal code\tType\tAmount\n" \
                            "Cogito\t1200\tMarketing\t432320\tExpense\t400")

      assert_equal({ "Area total" => "Area Budget", "Budget name" => "Budget", "Budget amount" => "Amount" },
                   import.column_mapping.slice("Area total", "Budget name", "Budget amount"))
      assert import.valid?, import.errors.to_sentence
      assert_equal "Marketing", import.entries.sole.row[:name]
    end

    def build_import(data, input_type: :paste, existing_budgets: [], existing_areas: [], people: [])
      BudgetImport.new(data, input_type: input_type, financial_year: @year,
                             cost_centre: @cost_centre, existing_budgets: existing_budgets,
                             existing_areas: existing_areas, people: people)
    end

    # A "Props" line in an area Bob owns, plus Alice, whom the sheet names.
    # +own_owners+ also puts Alice on the line's own owner rows.
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

    test "a matched budget with no cost centre is adopted, whether or not its figure moved" do
      moved = create_reimbursements_budget(name: "Venue hire", initial_budget: 1000)
      same = create_reimbursements_budget(name: "Bar", initial_budget: 1200)

      import = build_import(tsv("Venue hire\t4000\tExpense\t1200\t\t", "Bar\t4000\tExpense\t1200\t\t"),
                            existing_budgets: [ moved, same ])

      assert_equal %i[revise unchanged], import.entries.map(&:bucket)
      assert_equal [ moved, same ].map { |b| { budget_id: b.record_id, cost_centre: @cost_centre } },
                   import.adoptions
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

    # --- Strict column matching -----------------------------------------------

    test "two fields resolving to one column is refused, not guessed" do
      headers = "Initial budget name\tNominal code\tType\tOwner emails"
      row = "Props\t4000\tExpense\t"
      import = build_import([ headers, row ].join("\n"))

      assert_not import.valid?
      assert_match(/read as both/i, import.errors.to_sentence)
      assert_match(/Budget name/, import.errors.to_sentence)
      assert_match(/Budget amount/, import.errors.to_sentence)
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
      # initial_budget is never rewritten by a re-import.
      assert_empty import.creates
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

    test "an unreadable row blocks the import" do
      { "Venue\t4100\tExpense\tabout a grand\t\t" => /about a grand/,
        "\t4000\tExpense\t1200\t\t" => /name/i,
        "Props\t4000\tCapital\t1200\t\t" => /Capital/ }.each do |row, error|
        import = build_import(tsv("Good\t4000\tExpense\t1200\t\t", row))

        assert_not_predicate import, :valid?, row
        assert_equal %i[create invalid], import.entries.map(&:bucket), row
        assert_match error, import.entries.last.error
      end
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

    # --- Areas -----------------------------------------------------------------

    test "a line naming an area that does not exist creates it" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_equal 1, import.entries_in(:create).size
      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
      assert_equal @cost_centre, import.area_creates.first[:cost_centre]
      assert_equal @year, import.area_creates.first[:financial_year]
      # A create's area rides in on #creates: never a re-home, and never unticked.
      assert_empty import.re_homes
      assert_equal [ "Cogito" ], import.area_creates_for([]).map { |a| a[:name] }
    end

    test "a line naming an existing area attaches to it rather than creating a second" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_empty import.area_creates
      assert_equal area.record_id, import.creates.first[:area_id]
    end

    test "every row landing in a new area is new, however its cell is cased" do
      sheet = <<~TSV
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tSet\t432320\tExpense\t500
        cogito\tProps\t432330\tExpense\t600
      TSV

      import = build_import(sheet)
      assert(import.entries.all? { |entry| import.area_new?(entry) })

      stored = build_import(sheet, existing_areas: [ area_named("Cogito") ])
      assert(stored.entries.none? { |entry| stored.area_new?(entry) })
    end

    test "a line with a blank Area column is left area-less" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        \tContingency\t\tExpense\t1000
      TSV

      assert_empty import.area_creates
      assert_nil import.creates.first[:area_id]
    end

    # --- The area's agreed total ---------------------------------------------

    test "the area's total is read once from the repeated column" do
      import = build_import(<<~TSV)
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t£1,200\tCogito: Marketing\t432320\tExpense\t400
        Cogito\t£1,200\tCogito: Other\t432320\tExpense\t800
      TSV

      assert import.valid?, import.errors.inspect
      assert_equal 1, import.area_creates.size
      assert_equal 1200, import.area_creates.first[:initial_budget]
    end

    # Area's uniqueness check folds accents (utf8mb4_unicode_ci) and match_key
    # does not: unrefused, Area.create! would 500 inside apply.
    test "an area whose name differs only by an accent blocks rather than 500ing the apply" do
      existing = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)

      import = build_import(<<~TSV, existing_areas: [ existing ])
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cógito\t1200\tMarketing\t432320\tExpense\t400
      TSV

      assert_not import.valid?
      assert_match(/"Cógito" and "Cogito" are the same area name/, import.errors.join(" "))
    end

    test "two new areas differing only by an accent block the import" do
      import = build_import(<<~TSV)
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t1200\tMarketing\t432320\tExpense\t400
        Cógito\t1200\tSet\t432330\tExpense\t300
      TSV

      assert_not import.valid?
      assert_match(/are the same area name/, import.errors.join(" "))
    end

    test "two different totals for one area block the import" do
      import = build_import(<<~TSV)
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
        Cogito\t1500\tCogito: Other\t432320\tExpense\t800
      TSV

      assert_not import.valid?
      assert_match(/Cogito/, import.errors.join(" "))
    end

    test "an unreadable Area total blocks the import and the message names the column and the area" do
      import = build_import(<<~TSV)
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t£1,2OO\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_not import.valid?
      assert_match(/Cogito/, import.entries.sole.error)
      assert_match(/Area total/, import.entries.sole.error)
    end

    # Blank is the normal state for an area with no agreed total yet.
    test "a blank Area total still imports fine and leaves the area's initial_budget nil" do
      import = build_import(<<~TSV)
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert import.valid?
      assert_nil import.area_creates.first[:initial_budget]
    end

    # initial_budget is write-once on an area as on a budget; a new figure is
    # reported as a revision instead, compared against #projected_amount so a
    # re-import reports it once.
    test "an area that already exists keeps its own figure, write-once on create" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1000)
      sheet = <<~TSV
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV
      import = build_import(sheet, existing_areas: [ area ])

      assert import.valid?
      assert_empty import.area_creates
      assert_equal [ { area_id: area.record_id, area_name: "Cogito",
                       from: BigDecimal("1000"), amount: BigDecimal("1200") } ],
                   import.area_revisions

      DatabaseStore.new.create_budget_update!(effective_date: Date.current, note: "x",
                                              created_by: nil, forecasts: import.area_revisions)
      assert_empty build_import(sheet, existing_areas: [ area.reload ]).area_revisions,
                   "the same revision must not be reported for ever"
    end

    # A blank column says "leave the total alone", never "set it to nothing".
    test "an unchanged or blank area total is not a revision" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1200)
      [ "1200", "" ].each do |total|
        import = build_import(<<~TSV, existing_areas: [ area ])
          Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
          Cogito\t#{total}\tCogito: Marketing\t432320\tExpense\t400
        TSV

        assert_empty import.area_revisions, total.inspect
      end
    end

    test "an area with no agreed total yet takes the sheet's figure as a revision" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tArea total\tBudget name\tNominal code\tType\tBudget amount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      revision = import.area_revisions.sole
      assert_nil revision[:from]
      assert_equal BigDecimal("1200"), revision[:amount]
    end

    # --- Re-homing a line the sheet disagrees with ---------------------------

    def area_named(name, financial_year: @year)
      create_reimbursements_area(name: name, cost_centre: @cost_centre,
                                 financial_year: financial_year)
    end

    # A "Cogito: Marketing" line now in +area+, and the import of a one-row
    # sheet filing it under +cell+ ("" for none).
    def marketing_re_home(area: nil, cell: "Cogito", existing_areas: [], initial_budget: nil)
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                            initial_budget: initial_budget,
                                            cost_centre: @cost_centre, financial_year: @year)
      import = build_import(<<~TSV, existing_budgets: [ budget ], existing_areas: existing_areas)
        Area\tBudget\tNominal code\tType\tAmount
        #{cell}\tCogito: Marketing\t432320\tExpense\t400
      TSV
      [ budget, import ]
    end

    # Same buckets whether or not the figure moved (this one has not), and an
    # ordinary re-home qualifies neither side.
    test "a sheet naming a different area than the budget currently has reports a re-home" do
      cogito = area_named("Cogito")
      improverts = area_named("Improverts")
      budget, import = marketing_re_home(area: improverts, initial_budget: 400,
                                         existing_areas: [ cogito, improverts ])

      assert_equal :unchanged, import.entries.sole.bucket
      re_home = import.re_homes.sole
      assert_equal budget.record_id, re_home[:budget_id]
      assert_equal "Improverts", re_home[:from_area_name]
      assert_equal "Cogito", re_home[:to_area_name]
      assert_equal cogito.record_id, re_home[:area_id]
      assert_nil re_home[:from_area_scope]
      assert_not re_home[:to_area_is_new]
    end

    test "a line already in the area the sheet names reports no re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    # On a re-import every line already exists, so only a re-home from nil
    # attaches lines to a new area.
    test "a matched line with no area at all is a re-home from nowhere" do
      budget, import = marketing_re_home

      re_home = import.re_homes.sole
      assert_equal budget.record_id, re_home[:budget_id]
      assert_nil re_home[:from_area_name]
      assert_equal "Cogito", re_home[:to_area_name]
      # A NAME, not an id: import_budgets! resolves it once the area exists.
      assert_equal "Cogito", re_home[:area_name]
      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
    end

    test "a budget in an area whose sheet leaves the Area cell blank is not a re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, cell: "", existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    test "a line with no area on either side is not a re-home" do
      _budget, import = marketing_re_home(cell: "")

      assert_empty import.re_homes
    end

    test "a re-typed area name is the same area, not a re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, cell: "cogito ",
                                          existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    # --- The same name in another year ---------------------------------------
    # A budget may hold last year's "Cogito"; comparing names would read that
    # as already there.

    test "a same-named area from another year is a re-home, and the label says which" do
      stale = area_named("Cogito", financial_year: FinancialYear.create!(label: "Fringe 2026"))
      _budget, import = marketing_re_home(area: stale)

      re_home = import.re_homes.sole
      assert_equal "Cogito", re_home[:from_area_name]
      assert_equal "Fringe 2026", re_home[:from_area_scope]
      assert_equal "Cogito", re_home[:to_area_name]
      assert re_home[:to_area_is_new], "this year has no Cogito yet, so one is about to be created"
    end

    # --- The owner sign-off gate ---------------------------------------------
    # Budget#owners resolves through the area, so an ownerless one switches the
    # gate off.

    test "a re-home into an area that names nobody reports the lost sign-off gate" do
      _budget, import = marketing_re_home

      assert_not import.re_homes.sole[:to_area_has_owners],
                 "an area this import is about to create has no owners at all"
    end

    test "a re-home into an area that names somebody does not" do
      cogito = area_named("Cogito")
      cogito.sync_owner_ids!([ create_reimbursements_person(name: "Alice",
                                                            email: "alice@example.com").id ])
      _budget, import = marketing_re_home(existing_areas: [ cogito.reload ])

      assert import.re_homes.sole[:to_area_has_owners]
    end

    # The warning reads this import's own owner column too: a sheet naming an
    # owner for the target area leaves the gate standing.
    def marketing_with_owner(owner_cell, existing_areas: [], people: [])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", cost_centre: @cost_centre,
                                            financial_year: @year)
      build_import(<<~TSV, existing_budgets: [ budget ], existing_areas: existing_areas, people: people)
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\t#{owner_cell}
      TSV
    end

    test "a re-home into an area this import gives an owner does not report a lost gate" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")

      import = marketing_with_owner("alice@example.com", people: [ alice ])

      assert import.re_homes.sole[:to_area_has_owners],
             "the sheet names Alice for Cogito, so the gate still applies"
    end

    test "a re-home into an area whose only named owner is unknown still reports it" do
      import = marketing_with_owner("gone@example.com", existing_areas: [ area_named("Cogito") ])

      assert_not import.re_homes.sole[:to_area_has_owners],
                 "no Person is ever created from a bare email, so the area still names nobody"
    end

    # --- An area nothing lands in is not created -----------------------------

    test "unticking the only re-home into a new area stops it being created" do
      _budget, import = marketing_re_home

      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
      assert_empty import.area_creates_for([])
      assert_equal [ "Cogito" ], import.area_creates_for(import.re_homes).map { |a| a[:name] }
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

      # A stale email must not stop thirty lines landing.
      assert_predicate import, :valid?
      assert_equal [ "gone@example.com" ], import.unknown_owner_emails
      assert_equal [ alice.id.to_s ], import.creates.first[:owner_ids]
    end

    # --- The sheet's owner column names the AREA ------------------------------

    test "a matched line in an area sends the sheet's owner to the AREA, not its own rows" do
      budget, alice, bob = props_in_area_owned_by_bob
      sheet = tsv("Props\t4000\tExpense\t1000\talice@example.com\t")

      import = build_import(sheet, existing_budgets: [ budget ], people: [ alice, bob ])

      assert_empty import.owner_syncs,
                   "Budget#owners reads through the area, so the line's own rows are moot"
      sync = import.area_owner_syncs.sole
      assert_equal budget.area.record_id, sync[:area_id]
      # Bob is not on the sheet and survives it: a sync only ever adds.
      assert_equal [ alice.record_id, bob.record_id ].sort, sync[:owner_ids].sort

      DatabaseStore.new.add_area_owners!(budget.area.record_id, [ alice.record_id ])
      again = build_import(sheet, existing_budgets: [ budget.reload ], people: [ alice, bob ])
      assert_empty again.area_owner_syncs, "the same sync must not be reported for ever"
    end

    # --- What the preview's submit button counts ----------------------------
    # The button is disabled when nothing will happen, so a bucket the count
    # forgets cannot be applied at all.

    test "the button's count covers every kind of work an apply does" do
      arguments = DatabaseStore.instance_method(:import_budgets!).parameters
                               .filter_map { |kind, name| name if [ :key, :keyreq ].include?(kind) }
      # note and created_by name the revision log; they are not work.
      assert_equal (arguments - [ :note, :created_by ]).sort,
                   build_import(tsv("Props\t4000\tExpense\t1200\t\t")).apply_work.keys.sort
    end

    test "an owner-only sheet is something to import" do
      budget, alice, bob = props_in_area_owned_by_bob

      # Same figure, line already in the area: the only work is the owner.
      import = build_import(tsv("Props\t4000\tExpense\t1000\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice, bob ])

      assert_predicate import, :valid?
      work = import.apply_work.each_value.reject { |_, count| count.zero? }
      assert_equal [ [ "area owner update", 1 ] ], work
    end

    test "a re-home into a new area counts the area and the moved line" do
      elsewhere = create_reimbursements_area(name: "Improverts", financial_year: @year,
                                             cost_centre: @cost_centre)
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000, area: elsewhere,
                                            financial_year: @year, cost_centre: @cost_centre)
      sheet = [ [ "Area", "Area Budget", "Budget name", "Nominal code", "Type", "Amount" ].join("\t"),
                [ "Cogito", "", "Props", "4000", "Expense", "1000" ].join("\t") ].join("\n")

      import = build_import(sheet, existing_budgets: [ budget ], existing_areas: [ elsewhere ])

      work = import.apply_work.each_value.reject { |_, count| count.zero? }
      assert_equal [ [ "new area", 1 ], [ "moved line", 1 ] ], work
    end

    # One owner column per line, so two lines of one area name two people, and
    # both are meant.
    test "an area's owners are the union of what its lines name" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      marketing = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                               cost_centre: @cost_centre, financial_year: @year)
      other = create_reimbursements_budget(name: "Cogito: Other", area: area,
                                           cost_centre: @cost_centre, financial_year: @year)

      sheet = <<~TSV
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\talice@example.com
        Cogito\tCogito: Other\t432320\tExpense\t800\tbob@example.com
      TSV
      import = build_import(sheet, existing_budgets: [ marketing, other ],
                                   existing_areas: [ area ], people: [ alice, bob ])

      sync = import.area_owner_syncs.sole
      assert_equal area.record_id, sync[:area_id]
      assert_equal [ alice.record_id, bob.record_id ].sort, sync[:owner_ids].sort
      assert_empty import.owner_syncs, "an area-bound line must not write its own owner rows"
    end

    test "an area-less line still syncs its own owners" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      budget = create_reimbursements_budget(name: "Contingency", cost_centre: @cost_centre,
                                            financial_year: @year)

      import = build_import(<<~TSV, existing_budgets: [ budget ], people: [ alice ])
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        \tContingency\t\tExpense\t1000\talice@example.com
      TSV

      assert_empty import.area_owner_syncs
      assert_equal [ { budget_id: budget.record_id, owner_ids: [ alice.record_id ] } ], import.owner_syncs
    end

    # Otherwise every re-import would report an owner update for ever.
    test "a sheet naming a subset of an area's owners reports nothing" do
      budget, _alice, bob = props_in_area_owned_by_bob

      import = build_import(tsv("Props\t4000\tExpense\t1000\tbob@example.com\t"),
                            existing_budgets: [ budget ], people: [ bob ])

      assert_empty import.area_owner_syncs
    end

    # Like #creates' area: by name, resolved inside import_budgets!.
    test "an area this import creates is named rather than identified" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")

      import = build_import(<<~TSV, people: [ alice ])
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\talice@example.com
      TSV

      sync = import.area_owner_syncs.sole
      assert_nil sync[:area_id]
      assert_equal "Cogito", sync[:area_name]
      assert_equal [ alice.record_id ], sync[:owner_ids]
    end

    # An unknown address is never invented as a Person.
    test "an owner email that matched nobody adds nothing to the area" do
      import = build_import(<<~TSV, existing_areas: [ area_named("Cogito") ])
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\tgone@example.com
      TSV

      assert_empty import.area_owner_syncs
      assert_equal [ "gone@example.com" ], import.unknown_owner_emails
    end

    # Written both places on purpose: the move depends on the re-home's tick.
    test "an area-less line the sheet re-homes syncs its own owners as well as the area's" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", cost_centre: @cost_centre,
                                            financial_year: @year)
      area = area_named("Cogito")

      sheet = <<~TSV
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\talice@example.com
      TSV
      import = build_import(sheet, existing_budgets: [ budget ], existing_areas: [ area ],
                                   people: [ alice ])

      assert_equal [ alice.record_id ], import.owner_syncs.sole[:owner_ids]
      assert_equal [ alice.record_id ], import.area_owner_syncs.sole[:owner_ids]
    end

    # --- What the preview names ----------------------------------------------

    test "the preview names an area's resulting owners, marking the ones being added" do
      budget, alice, bob = props_in_area_owned_by_bob

      import = build_import(tsv("Props\t4000\tExpense\t1000\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice, bob ])

      set = import.area_owner_sets.sole
      assert_equal "Cogito", set[:area_name]
      assert_not set[:area_is_new]
      assert_nil set[:area_scope]
      assert_equal({ "Bob" => false, "Alice" => true },
                   set[:owners].to_h { |owner| [ owner[:name], owner[:added] ] })
    end

    # A blank cell reaches the line's own area, here last year's Cogito, which
    # no re-home names; unqualified it would read as a second bare Cogito.
    test "an out-of-scope area the owner column reaches is qualified, not a second bare Cogito" do
      stale = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                         financial_year: FinancialYear.create!(label: "Fringe 2026"))
      here = area_named("Cogito")
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      stranded = create_reimbursements_budget(name: "Cogito: Set", area: stale,
                                              cost_centre: @cost_centre, financial_year: @year)
      placed = create_reimbursements_budget(name: "Cogito: Marketing", area: here,
                                            cost_centre: @cost_centre, financial_year: @year)

      sheet = <<~TSV
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        \tCogito: Set\t432320\tExpense\t500\tbob@example.com
        Cogito\tCogito: Marketing\t432320\tExpense\t400\talice@example.com
      TSV
      import = build_import(sheet, existing_budgets: [ stranded, placed ],
                                   existing_areas: [ here ], people: [ alice, bob ])

      assert_equal [ "Cogito", "Cogito" ], import.area_owner_sets.map { |set| set[:area_name] },
                   "both areas are called Cogito — the qualification is all that separates them"
      assert_equal({ "Fringe 2026" => [ "Bob" ], nil => [ "Alice" ] },
                   import.area_owner_sets.to_h { |set|
                     [ set[:area_scope], set[:owners].map { |owner| owner[:name] } ]
                   })
    end

    # --- Round-tripping an upload through the preview -------------------------

    test "to_tsv re-parses to the same rows" do
      original = build_import(tsv("Props\t4000\tExpense\t£1,200\talice@example.com\tSome notes"))

      round_tripped = build_import(original.to_tsv, input_type: :canonical_tsv)

      assert_equal original.entries.map(&:row), round_tripped.entries.map(&:row)
    end

    test "to_tsv survives a tab or newline typed into an uploaded cell" do
      file = xlsx_upload(xlsx_sheet([ "Props", "4000", "Expense", "100", "", "one\ttwo\nthree" ]), sheet: "Budget")
      import = build_import(file, input_type: :xlsx)

      round_tripped = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal "Props", import.entries.sole.row[:name]
      assert_equal BigDecimal("100"), import.entries.sole.row[:amount]
      assert_equal import.entries.map(&:row), round_tripped.entries.map(&:row)
      assert_equal "one\ttwo\nthree", round_tripped.entries.sole.row[:notes]
    end

    # Only an xlsx cell can hold a tab or newline, so they arrive escaped and
    # must leave escaped.
    test "an escaped cell coming back from the preview is unescaped once" do
      import = build_import(tsv("Costume\\nrepairs\t4000\tExpense\t100\t\tone\\ttwo"),
                            input_type: :canonical_tsv)

      assert_equal "Costume\nrepairs", import.entries.sole.row[:name]
      assert_equal "one\ttwo", import.entries.sole.row[:notes]

      again = build_import(import.to_tsv, input_type: :canonical_tsv)

      assert_equal "Costume\nrepairs", again.entries.sole.row[:name]
      assert_equal "one\ttwo", again.entries.sole.row[:notes]
    end

    # #to_tsv escapes every cell, so apply must unescape every cell, the amounts included, or
    # an unreadable figure changes each time the sheet makes the round trip.
    test "an unreadable amount holding a backslash comes back from the round trip unchanged" do
      first = build_import(tsv("Props\t4000\tExpense\t12\\ quid\t\t"))

      again = build_import(first.to_tsv, input_type: :canonical_tsv)

      assert_equal "12\\ quid", again.entries.sole.row[:raw_amount]
      assert_equal first.to_tsv, again.to_tsv
    end

    # In the operator's own paste a backslash is a backslash: only the preview's
    # hidden field is this class's own output. The name is the match key.
    test "a pasted backslash name still matches the budget it names" do
      existing = create_reimbursements_budget(name: "Costume\\next week", initial_budget: 1000,
                                              cost_centre: @cost_centre, financial_year: @year)

      import = build_import(tsv("Costume\\next week\t4000\tExpense\t1200\t\tC:\\temp\\report.pdf"),
                            existing_budgets: [ existing ])

      assert_equal "Costume\\next week", import.entries.sole.row[:name]
      assert_equal "C:\\temp\\report.pdf", import.entries.sole.row[:notes]
      assert_equal :revise, import.entries.sole.bucket
    end

    # --- The sheet still writes the prefix the rename took off ----------------
    # Matched on area plus bare name, in both spellings and both directions.

    # A show whose lines have been through the rename: bare names in the area.
    def renamed_cogito(*names)
      area = area_named("Cogito")
      budgets = names.map do |name|
        create_reimbursements_budget(name: "Cogito: #{name}", area: area, initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
      end
      Reimbursements::AreaRename.strip!
      [ area, budgets.map(&:reload) ]
    end

    # A one-line sheet filing +name+ under +cell+.
    def area_sheet(cell, name, amount: 500)
      <<~TSV
        Area\tBudget\tNominal code\tType\tAmount
        #{cell}\t#{name}\t432320\tExpense\t#{amount}
      TSV
    end

    test "the sheet the committee already has still revises its renamed lines" do
      area, budgets = renamed_cogito("Marketing", "Set")

      import = build_import(<<~TSV, existing_budgets: budgets, existing_areas: [ area ])
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t500
        Cogito\tCogito: Set\t432330\tExpense\t600
      TSV

      assert_empty import.entries_in(:create), "every line already exists under its bare name"
      assert_equal budgets.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
      assert_empty import.absent_budgets
      assert_empty import.re_homes, "the lines are already in the area the sheet names"
    end

    test "a stored line is matched by its area plus either spelling of its name" do
      areas = %w[Cogito Improverts].index_with { |name| area_named(name) }
      {
        # Not yet renamed, sheet already bare.
        [ "Cogito", "Cogito: Marketing", "Cogito", "Marketing" ] => :revise,
        # The same, with no Area cell.
        [ "Cogito", "Cogito: Marketing", "", "Marketing" ] => :revise,
        # The whitespace the rename tolerated.
        [ "Improverts", "Retreat", "Improverts", "Improverts:  Retreat" ] => :revise,
        # Another show's prefix is part of the name, not stripped.
        [ "Cogito", "Retreat", "Cogito", "Improverts: Retreat" ] => :create,
        [ nil, "Contingency", "", "Contingency" ] => :revise
      }.each do |(area_name, stored, cell, typed), bucket|
        area = areas[area_name]
        budget = create_reimbursements_budget(name: stored, area: area, initial_budget: 400,
                                              financial_year: @year, cost_centre: @cost_centre)

        import = build_import(area_sheet(cell, typed),
                              existing_budgets: [ budget ], existing_areas: [ area ].compact)

        assert_equal bucket, import.entries.sole.bucket, [ area_name, stored, cell, typed ].inspect
      end
    end

    # The committee's untouched old file: prefixed names, no Area column.
    test "the old sheet with no Area column still revises its renamed lines" do
      _area, budgets = renamed_cogito("Marketing", "Set")

      import = build_import(tsv("Cogito: Marketing\t432320\tExpense\t500\t\t",
                                "Cogito: Set\t432330\tExpense\t600\t\t"),
                            existing_budgets: budgets)

      assert_empty import.entries_in(:create)
      assert_equal budgets.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
      assert_empty import.absent_budgets
    end

    # A loose line literally named "Cogito: Marketing" collides with Cogito's
    # own "Marketing".
    test "a line named like another's prefixed spelling blocks the import" do
      area, budgets = renamed_cogito("Marketing")
      never_backfilled = create_reimbursements_budget(name: "Cogito: Marketing", initial_budget: 400,
                                                      financial_year: @year,
                                                      cost_centre: @cost_centre)

      import = build_import(tsv("Cogito: Marketing\t432320\tExpense\t500\t\t"),
                            existing_budgets: budgets + [ never_backfilled ],
                            existing_areas: [ area ])

      assert_not import.valid?
      assert_match(/matches more than one budget/, import.entries.sole.error)
    end

    # The duplicate check compares what the sheet typed, so this is caught on
    # the stored line instead.
    test "two spellings of one line in one sheet blocks the import" do
      _area, budgets = renamed_cogito("Marketing")

      import = build_import(tsv("Marketing\t432320\tExpense\t500\t\t",
                                "Cogito: Marketing\t432320\tExpense\t600\t\t"),
                            existing_budgets: budgets)

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert_match(/is named more than once in this sheet/, import.entries.first.error)
      assert_match(/"Marketing" \(no area\) and "Cogito: Marketing" \(no area\)/,
                   import.entries.first.error)
    end

    # --- Two lines that answer to one key ------------------------------------

    # Two shows each running a bare "Marketing" line, keyed by show. Improverts
    # is built FIRST: a plain-name fallback would answer with it, so a test
    # asserting Cogito's line can only pass on the area key.
    def two_shows_running_marketing
      %w[Improverts Cogito].to_h do |show|
        area = area_named(show)
        [ show, create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 400,
                                             financial_year: @year, cost_centre: @cost_centre) ]
      end
    end

    def areas_named(shows) = shows.values.map(&:area)

    test "the sheet's area picks between two shows' lines of the same name, in either spelling" do
      shows = two_shows_running_marketing

      [ "Cogito: Marketing", "Marketing" ].each do |typed|
        import = build_import(area_sheet("Cogito", typed),
                              existing_budgets: shows.values, existing_areas: areas_named(shows))

        assert_equal shows["Cogito"].record_id, import.entries.sole.budget.record_id, typed
        assert_equal [ shows["Improverts"].record_id ], import.absent_budgets.map(&:record_id), typed
      end
    end

    test "an area holding two lines that collapse to one key blocks the import" do
      area = area_named("Cogito")
      budgets = [ "Marketing", "Cogito: Marketing" ].map do |name|
        create_reimbursements_budget(name: name, area: area, initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
      end

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: budgets, existing_areas: [ area ])

      assert_not import.valid?
      # Names the AREA too: "Marketing" twice says nothing.
      assert_match(/matches more than one budget/, import.entries.sole.error)
      assert_match(/in Cogito/, import.entries.sole.error)
    end

    test "a sheet writing both spellings of one line blocks the import" do
      area, budgets = renamed_cogito("Marketing")

      import = build_import(<<~TSV, existing_budgets: budgets, existing_areas: [ area ])
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        Cogito\tCogito: Marketing\t432320\tExpense\t600
      TSV

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert(import.entries_in(:invalid).all? { |entry| entry.error.include?("named more than once") },
             "both rows name the same budget, which is the duplicate rule, not a match failure")
    end

    # --- A loose line and an area's line of one name --------------------------
    # Two lines. The Area cell disambiguates, and a blank cell means the line
    # in no area.

    test "the same name with an Area cell and without is two lines, not a collision" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tMarketing\t432330\tExpense\t600
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal 2, import.entries_in(:create).size
      assert_equal [ "Cogito" ], import.entries.filter_map { |entry| entry.area_name.presence }
    end

    test "a loose line and an area's line of the same name are two lines, not a collision" do
      cogito = area_named("Cogito")
      in_area = create_reimbursements_budget(name: "Marketing", area: cogito, initial_budget: 400,
                                             financial_year: @year, cost_centre: @cost_centre)
      loose = create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                           financial_year: @year, cost_centre: @cost_centre)

      import = build_import(<<~TSV, existing_budgets: [ in_area, loose ], existing_areas: [ cogito ])
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tMarketing\t432320\tExpense\t900
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal [ in_area.record_id, loose.record_id ].sort,
                   import.entries_in(:revise).map { |entry| entry.budget.record_id }.sort
      assert_empty import.re_homes, "neither row asks to move a line into another show"
    end

    test "a bare name with no area cell still blocks when only area-bound lines could match" do
      shows = two_shows_running_marketing

      import = build_import(tsv("Marketing\t432320\tExpense\t500\t\t"),
                            existing_budgets: shows.values, existing_areas: areas_named(shows))

      assert_not import.valid?, "the sheet does not say which show this is"
      assert_match(/matches more than one budget/, import.entries.sole.error)
    end

    # Budget names are not unique, so two loose lines of one name happen.
    test "two lines in no area of one name block a row that cannot separate them" do
      cogito = area_named("Cogito")
      in_area = create_reimbursements_budget(name: "Marketing", area: cogito, initial_budget: 400,
                                             financial_year: @year, cost_centre: @cost_centre)
      loose = Array.new(2) do
        create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
      end

      import = build_import(tsv("Marketing\t432320\tExpense\t500\t\t"),
                            existing_budgets: loose + [ in_area ], existing_areas: [ cogito ])

      assert_not import.valid?
      assert_match(/matches more than one budget/, import.entries.sole.error)
    end

    # Both rows name Cogito's Marketing, one by cell and one by prefix: the
    # likeliest mid-transition sheet. They already agree about the area, so
    # the message must not suggest an Area cell.
    test "an area cell and the same area's prefix are one line, not two" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
      TSV

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert_match(/named more than once in this sheet/, import.entries.first.error)
      assert_match(/already names Cogito, so an Area cell would not tell them apart/,
                   import.entries.first.error)
      assert_no_match(/told apart by their area/, import.entries.first.error)
    end

    # Created loose with the prefix, the next converted sheet would create it
    # again inside Cogito. The preview must agree with #creates about it.
    test "a create adopts the area its own name names, and drops the prefix" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tSet\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal [ %w[Set Cogito], %w[Marketing Cogito] ],
                   import.creates.map { |create| [ create[:name], create[:area_name] ] }
      adopted = import.entries.last
      assert_equal "Cogito", import.area_name_for(adopted)
      assert import.area_adopted?(adopted)
      assert_not import.area_adopted?(import.entries.first), "that row's own cell says Cogito"
    end

    test "a create that adopts an area sends its owner there, not to its own rows" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")

      import = build_import(<<~TSV, people: [ alice ])
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tSet\t432320\tExpense\t500\t
        \tCogito: Marketing\t432330\tExpense\t600\talice@example.com
      TSV

      assert_equal [ "Cogito" ], import.area_owner_sets.map { |set| set[:area_name] }
      assert_equal [ "Alice" ], import.area_owner_sets.sole[:owners].map { |owner| owner[:name] }
    end

    # Moving a stored line on a prefix is a bigger claim than naming a new one.
    test "a matched row is not re-homed on the strength of its prefix" do
      stale = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                         financial_year: FinancialYear.create!(label: "Fringe 2026"))
      here = area_named("Cogito")
      stranded = create_reimbursements_budget(name: "Cogito: Set", area: stale, initial_budget: 400,
                                              cost_centre: @cost_centre, financial_year: @year)

      import = build_import(<<~TSV, existing_budgets: [ stranded ], existing_areas: [ here ])
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tCogito: Set\t432330\tExpense\t600
      TSV

      assert_equal :revise, import.entries.last.bucket
      assert_empty import.re_homes, "the cell is blank, so nothing asked for the line to move"
    end

    # Compared by RECORD: by name, another year's Cogito reads as agreement.
    test "a matched line in a same-named area from another year is qualified, not silent" do
      stale = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                         financial_year: FinancialYear.create!(label: "Fringe 2026"))
      here = area_named("Cogito")
      budget = create_reimbursements_budget(name: "Marketing", area: stale, initial_budget: 400,
                                            cost_centre: @cost_centre, financial_year: @year)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ budget ], existing_areas: [ here ])

      assert_equal budget.record_id, import.entries.sole.budget.record_id
      assert_match(/Fringe 2026/, import.entries.sole.matched_area_label)
    end

    # The first import of a year is all creates, so a label here would be on
    # every row.
    test "a create states no matched line, however its Area cell reads" do
      import = build_import(area_sheet("Cogito", "Marketing"))

      assert_equal :create, import.entries.sole.bucket
      assert_nil import.entries.sole.matched_area_label
    end

    # A label here would repeat the cell on every row.
    test "a matched line in the area the sheet named is not labelled" do
      here = area_named("Cogito")
      budget = create_reimbursements_budget(name: "Marketing", area: here, initial_budget: 400,
                                            cost_centre: @cost_centre, financial_year: @year)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ budget ], existing_areas: [ here ])

      assert_nil import.entries.sole.matched_area_label
    end

    # Nothing merges, but the preview must link the create to the absence.
    test "an absent line the sheet re-creates under its own prefix is named as superseded" do
      cogito = area_named("Cogito")
      loose = create_reimbursements_budget(name: "Cogito: Marketing", initial_budget: 400,
                                           financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ loose ], existing_areas: [ cogito ])

      assert_equal [ "Marketing" ], import.creates.map { |create| create[:name] }
      assert_equal [ loose.record_id ], import.absent_budgets.map(&:record_id)
      assert_equal [ loose.record_id ], import.superseded_absent_budgets.map(&:record_id)
    end

    # A show's "Marketing" beside a standing one is a legitimate pair: only an
    # absent line whose OWN name carries the prefix is flagged.
    test "an absent line that carries no prefix is not reported as superseded" do
      cogito = area_named("Cogito")
      loose = create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                           financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Cogito: Marketing"),
                            existing_budgets: [ loose ], existing_areas: [ cogito ])

      assert_equal [ "Marketing" ], import.creates.map { |create| create[:name] },
                   "the create resolves to the same bare name the loose line already has"
      assert_equal [ loose.record_id ], import.absent_budgets.map(&:record_id)
      assert_empty import.superseded_absent_budgets
    end

    # Only an area the sheet names reads as a prefix. Read as one, the last two
    # rows would collapse onto one key and block.
    test "a prefix no row of the sheet names is part of the name" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Improverts\tMarketing\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
        \tCogito:Marketing\t432340\tExpense\t700
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal 3, import.entries_in(:create).size
    end

    # Several declined namesakes read as a list.
    test "the loose reading names every namesake it passed over" do
      shows = two_shows_running_marketing
      loose = create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                           financial_year: @year, cost_centre: @cost_centre)

      import = build_import(tsv("Marketing\t432320\tExpense\t900\t\t"),
                            existing_budgets: shows.values + [ loose ],
                            existing_areas: areas_named(shows))

      assert_equal loose.record_id, import.entries.sole.budget.record_id
      assert_match(/"Marketing" in Improverts and "Marketing" in Cogito are named the same/,
                   import.entries.sole.matched_note)
      assert_match(/if you meant one of those/, import.entries.sole.matched_note)
    end

    # This row pointed at Cogito and missed: the loose line is not what it meant.
    test "a row naming an area does not fall back to the line that is in no area" do
      improverts = area_named("Improverts")
      in_area = create_reimbursements_budget(name: "Marketing", area: improverts, initial_budget: 400,
                                             financial_year: @year, cost_centre: @cost_centre)
      loose = create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                           financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ loose, in_area ], existing_areas: [ improverts ])

      assert_not import.valid?
      assert_match(/matches more than one budget/, import.entries.sole.error)
      assert_empty import.re_homes, "a blocked row moves nothing"
    end

    # One line typed twice: the message counts the rows rather than listing one
    # label twice.
    test "the same name under one area twice is a duplicate, counted" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        Cogito\tMarketing\t432330\tExpense\t600
      TSV

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert_match(/"Marketing" \(Cogito\), 2 times/, import.entries.first.error)
      assert_match(/Name it once/, import.entries.first.error)
      assert_no_match(/its own Area cell/, import.entries.first.error)
    end

    # Area-less rows are keyed on their own names alone.
    test "two area-less rows are told apart by their own names" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tSet\t432320\tExpense\t500
        \tMarketing\t432330\tExpense\t600
        \tCogito: Marketing\t432340\tExpense\t700
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal 3, import.entries_in(:create).size
    end

    # Prefixed or bare, a row that names an area is identified BY that area.
    test "the same name under two areas is two lines, not a duplicate" do
      shows = two_shows_running_marketing
      spellings = [ [ "Cogito: Marketing", "Improverts: Marketing" ], [ "Marketing", "Marketing" ] ]

      spellings.each do |cogito, improverts|
        import = build_import(<<~TSV, existing_budgets: shows.values, existing_areas: areas_named(shows))
          Area\tBudget\tNominal code\tType\tAmount
          Cogito\t#{cogito}\t432320\tExpense\t500
          Improverts\t#{improverts}\t432330\tExpense\t600
        TSV

        assert import.valid?, "#{cogito.inspect}: #{import.errors.inspect}"
        assert_equal shows.values.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
      end
    end

    # A spelling lost under a degenerate name would be silent: the line would
    # just stop being findable.
    test "the split name index holds every spelling between its two halves" do
      names = [ "Marketing", "Cogito: Marketing", "Cogito:  Marketing", "cogito :  Marketing",
                ":", "Cogito: ", ": Marketing", "Cogito: Cogito: Marketing", "Improverts: Retreat" ]
      areas = [ nil, "Cogito", "cogito ", ":" ]

      names.product(areas).each do |name, area_name|
        budget = Budget.new(name: name, area: area_name && Area.new(name: area_name))
        halves = [ true, false ].map { |flag| BudgetImport.spelling_keys(budget, naming_area: flag) }
        expected = BudgetImport.name_spellings(name, area_name)
                               .map { |spelling| BudgetImport.match_key(spelling) }.uniq

        assert_equal expected.sort, halves.inject(:|).sort, "#{name.inspect} in #{area_name.inspect}"
        assert_empty halves.inject(:&), "#{name.inspect} in #{area_name.inspect}"
      end
    end

    # --- Two areas of one name -----------------------------------------------
    # Lenient year scoping puts an unstamped legacy area beside a real one.

    test "two areas of one name block the line that files into them" do
      here = area_named("Cogito")
      unstamped = Area.create!(name: "Cogito")
      budget = create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                            financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ budget ], existing_areas: [ here, unstamped ])

      assert_not import.valid?
      assert_match(/matches more than one area/, import.entries.sole.error)
      assert_match(/no financial year or cost centre/, import.entries.sole.error)
      assert_empty import.re_homes, "a blocked row moves nothing"
    end
  end
end
