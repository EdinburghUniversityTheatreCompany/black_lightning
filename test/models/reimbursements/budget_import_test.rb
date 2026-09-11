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

    # DERIVED, never retyped. A hardcoded six-column subset here is how Task
    # 2's Area column shifted every cell one place left and survived two tasks:
    # these sheets went on matching by header name and said nothing, and only
    # the system test — the one `bin/rails test` never runs — could catch it.
    HEADERS = ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t").freeze

    # TSV_HEADERS leads with the two AREA columns, so a row stating only a
    # budget line leaves them blank. The area tests below write their own
    # headers, because what they are testing IS those two columns.
    def tsv(*rows)
      ([ HEADERS ] + rows.map { |row| "\t\t#{row}" }).join("\n")
    end

    # The same padding for an xlsx row, which is an Array, not a String.
    def xlsx_sheet(*rows)
      [ HEADERS.split("\t") ] + rows.map { |row| [ "", "" ] + row }
    end

    # What the two blank cells above are padding PAST. A column inserted before
    # them shifts every row again, so state the assumption rather than leave it
    # in a "\t\t" literal.
    test "the sheet helpers' padding still matches the canonical column order" do
      assert_equal [ "Area", "Area Budget" ], BudgetImport::TSV_HEADERS.first(2)
    end

    def build_import(data, input_type: :paste, existing_budgets: [], existing_areas: [], people: [])
      BudgetImport.new(data, input_type: input_type, financial_year: @year,
                             cost_centre: @cost_centre, existing_budgets: existing_budgets,
                             existing_areas: existing_areas, people: people)
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
      file = xlsx_fixture(xlsx_sheet([ "Props", "4000", "Expense", "1200", "", "" ]))

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

    # --- Strict column matching -----------------------------------------------
    # A bare keyword ("budget") must never be read as a substring hint, or a
    # sheet naming both "Budget" and a column ending in "Budget" reads the wrong
    # one as the line's name; and two fields on one column must be refused
    # rather than guessed.

    test "a bare word is never read as a substring hint" do
      headers = "Area\tArea Budget\tBudget\tNominal code\tType\tAmount\tOwner emails\tNotes"
      row = "Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400\t\t"
      import = build_import([ headers, row ].join("\n"))

      assert_equal "Cogito: Marketing", import.entries.first.row[:name],
                   "the name must come from the Budget column, not from Area Budget"
    end

    test "two fields resolving to one column is refused, not guessed" do
      headers = "Initial budget name\tNominal code\tType\tOwner emails"
      row = "Props\t4000\tExpense\t"
      import = build_import([ headers, row ].join("\n"))

      assert_not import.valid?
      assert_match(/read as both/i, import.errors.to_sentence)
      assert_match(/Budget/, import.errors.to_sentence)
      assert_match(/Amount/, import.errors.to_sentence)
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

    # --- Areas -----------------------------------------------------------------
    # Matched by name within one (financial year, cost centre), the rule a
    # budget line and AreaBackfill both use. Never deleted by an import, for
    # absent_budgets' reason.

    test "a line naming an area that does not exist creates it" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
      assert_equal @cost_centre, import.area_creates.first[:cost_centre]
      assert_equal @year, import.area_creates.first[:financial_year]
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

    test "a line with a blank Area column is left area-less" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        \tContingency\t\tExpense\t1000
      TSV

      assert_empty import.area_creates
      assert_nil import.creates.first[:area_id]
    end

    # --- The area's agreed total ---------------------------------------------
    # The column repeats down every row of an area, because the sheet has one
    # row per budget line rather than one per area.

    test "the area's total is read once from the repeated column" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
        Cogito\t1200\tCogito: Other\t432320\tExpense\t800
      TSV

      assert_equal 1, import.area_creates.size
      assert_equal 1200, import.area_creates.first[:initial_budget]
    end

    # Area's uniqueness validation queries under utf8mb4_unicode_ci, which folds
    # accents; the importer's own match_key folds only case and spacing. Without
    # this the name reached #area_creates as NEW and Area.create! raised inside
    # apply's transaction — a 500 losing the operator's whole paste.
    test "an area whose name differs only by an accent blocks rather than 500ing the apply" do
      existing = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)

      import = build_import(<<~TSV, existing_areas: [ existing ])
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cógito\t1200\tMarketing\t432320\tExpense\t400
      TSV

      assert_not import.valid?
      assert_match(/"Cógito" and "Cogito" are the same area name/, import.errors.join(" "))
      # And the refusal is doing real work: the database would refuse it too.
      assert_raises(ActiveRecord::RecordInvalid) do
        Area.create!(name: "Cógito", cost_centre: @cost_centre, financial_year: @year)
      end
    end

    test "two new areas differing only by an accent block the import" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tMarketing\t432320\tExpense\t400
        Cógito\t1200\tSet\t432330\tExpense\t300
      TSV

      assert_not import.valid?
      assert_match(/are the same area name/, import.errors.join(" "))
    end

    test "an area named the same way twice over is not an accent clash" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tMarketing\t432320\tExpense\t400
        Cogito\t1200\tSet\t432330\tExpense\t300
      TSV

      assert import.valid?, import.errors.inspect
      assert_equal 1, import.area_creates.size
    end

    test "two different totals for one area block the import" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
        Cogito\t1500\tCogito: Other\t432320\tExpense\t800
      TSV

      assert_not import.valid?
      assert_match(/Cogito/, import.errors.join(" "))
    end

    test "a typed £1,200 is stored as 1200, not 0" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t£1,200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_equal 1200, import.area_creates.first[:initial_budget]
    end

    # An unreadable Area Budget is a BLOCKING row error, the same as an
    # unreadable Amount — reading it as "unstated" would create the area with
    # no agreed total and nobody told, which is silent wrong money.
    test "an unreadable Area Budget blocks the import and the message names the area" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t£1,2OO\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_not import.valid?
      assert_match(/Cogito/, import.entries.sole.error)
    end

    # Blank is legitimate and must stay legitimate: an area with no agreed
    # total is the normal state for every area Phase 1's backfill created.
    test "a blank Area Budget still imports fine and leaves the area's initial_budget nil" do
      import = build_import(<<~TSV)
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert import.valid?
      assert_nil import.area_creates.first[:initial_budget]
    end

    # initial_budget is write-once on an area exactly as it is on a budget, so
    # Area#variance keeps meaning "drift from the figure the committee agreed".
    # The revised figure is not dropped, though — it is REPORTED and logged as
    # a forecast, which is the twin of what a line revision does.
    test "an area that already exists keeps its own figure, write-once on create" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1000)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert import.valid?
      assert_empty import.area_creates
      assert_equal [ { area_id: area.record_id, area_name: "Cogito",
                       from: BigDecimal("1000"), amount: BigDecimal("1200") } ],
                   import.area_revisions
    end

    test "an unchanged area total is not reported as a revision" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1200)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_empty import.area_revisions
    end

    # A blank column says "leave the total alone", never "set it to nothing" —
    # the same rule a blank Amount follows on a budget line.
    test "a blank Area Budget is not a revision" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1200)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_empty import.area_revisions
    end

    # Compared against #projected_amount, so a second re-import measures the
    # sheet against the LAST forecast rather than re-reporting the same
    # revision for ever — the convergence property the owner syncs needed too.
    test "an area total revision converges: a re-import reports it once" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year, initial_budget: 1000)
      sheet = <<~TSV
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      first = build_import(sheet, existing_areas: [ area ])
      assert_equal 1, first.area_revisions.size

      DatabaseStore.new.create_budget_update!(effective_date: Date.current, note: "x",
                                              created_by: nil,
                                              forecasts: first.area_revisions)

      second = build_import(sheet, existing_areas: [ area.reload ])
      assert_empty second.area_revisions, "the same revision must not be reported for ever"
    end

    test "an area with no agreed total yet takes the sheet's figure as a revision" do
      area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                        financial_year: @year)
      import = build_import(<<~TSV, existing_areas: [ area ])
        Area\tArea Budget\tBudget\tNominal code\tType\tAmount
        Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
      TSV

      revision = import.area_revisions.sole
      assert_nil revision[:from]
      assert_equal BigDecimal("1200"), revision[:amount]
    end

    # --- Re-homing a line the sheet disagrees with ---------------------------
    # Somebody moved that budget by hand, so a sheet naming a different area
    # REPORTS it rather than doing it — #absent_budgets' temperament. Ticked by
    # default, like Reconcile's offsetting pairs; unticking leaves the hand-made
    # grouping alone.

    def area_named(name, financial_year: @year)
      create_reimbursements_area(name: name, cost_centre: @cost_centre,
                                 financial_year: financial_year)
    end

    # A "Cogito: Marketing" line and the import of a one-row sheet filing it
    # under +cell+ ("" for a sheet that says nothing). +area+ is where the line
    # sits NOW; +existing_areas+ is what the year already holds. Returns both,
    # because most of these tests assert on the budget's own id.
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

    test "a sheet naming a different area than the budget currently has reports a re-home" do
      cogito = area_named("Cogito")
      improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                              financial_year: @year)
      budget, import = marketing_re_home(area: improverts, existing_areas: [ cogito, improverts ])

      re_home = import.re_homes.sole
      assert_equal budget.record_id, re_home[:budget_id]
      assert_equal "Improverts", re_home[:from_area_name]
      assert_equal "Cogito", re_home[:to_area_name]
    end

    test "a line already in the area the sheet names reports no re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    # The case that closes Task 2's orphaned-area gap: on a re-import every
    # line already exists, so #area_creates mints the area and NOTHING would
    # attach a budget to it — only :create lines carry an area_id. A re-home
    # FROM NIL is what attaches them.
    test "a matched line with no area at all is a re-home from nowhere" do
      budget, import = marketing_re_home

      re_home = import.re_homes.sole
      assert_equal budget.record_id, re_home[:budget_id]
      assert_nil re_home[:from_area_name]
      assert_equal "Cogito", re_home[:to_area_name]
      # Carried as a NAME, not an id: this area doesn't exist yet, so
      # import_budgets! resolves it once #area_creates has run — exactly what
      # #creates does for a new line naming a new area.
      assert_equal "Cogito", re_home[:area_name]
      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
    end

    # A blank cell means "the sheet says nothing", the same reading bucket_for
    # gives a blank Amount — never "move this line out of its area".
    test "a budget in an area whose sheet leaves the Area cell blank is not a re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, cell: "", existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    test "a line with no area on either side is not a re-home" do
      _budget, import = marketing_re_home(cell: "")

      assert_empty import.re_homes
    end

    # A :create line has nothing to move — its area rides in on #creates.
    test "a new line is never a re-home" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_equal 1, import.entries_in(:create).size
      assert_empty import.re_homes
    end

    # Same buckets as #adoptions and #owner_syncs: a matched line is matched
    # whether or not its figure moved.
    test "a re-home does not depend on the figure having moved" do
      cogito = area_named("Cogito")
      # A REAL from-area, not the nil default: otherwise this is a second
      # from-nil test wearing another name, and it dies for that reason too.
      improverts = area_named("Improverts")
      budget, import = marketing_re_home(area: improverts, initial_budget: 400,
                                         existing_areas: [ cogito, improverts ])

      assert_equal :unchanged, import.entries.sole.bucket
      assert_equal [ budget.record_id ], import.re_homes.map { |r| r[:budget_id] }
      # The target already exists here, so it travels as an id.
      assert_equal cogito.record_id, import.re_homes.sole[:area_id]
    end

    # Keyed by budget id, not row position: a re-import with the rows reordered
    # must not apply a tick to a different line.
    test "the re-home checkbox key is the budget id" do
      budget, import = marketing_re_home(existing_areas: [ area_named("Cogito") ])

      assert_equal budget.record_id, import.re_homes.sole[:key]
      assert_equal "Cogito: Marketing", import.re_homes.sole[:budget_name]
    end

    # Case and stray spaces are how a committee retypes an area name, so the
    # same match_key a budget line uses decides whether the line has moved.
    test "a re-typed area name is the same area, not a re-home" do
      cogito = area_named("Cogito")
      _budget, import = marketing_re_home(area: cogito, cell: "cogito ",
                                          existing_areas: [ cogito ])

      assert_empty import.re_homes
    end

    # --- The same name in another year ---------------------------------------
    # Areas are named per show and shows recur, so "Cogito" exists once per
    # Fringe — and a budget in THIS year may legitimately hold LAST year's
    # area: inherit_area_scoping fills blanks only and never checks the year,
    # and BudgetsController appends the budget's own area to the scoped select
    # precisely so such a row survives a save. Comparing on the NAME read that
    # as "already there" and reported nothing, while the line's spend kept
    # rolling up into the other year's total (Area#committed_amount sums its
    # budgets with no year filter) and that year's owners kept gating the claim.

    test "a same-named area from another year is a re-home, and the label says which" do
      stale = area_named("Cogito", financial_year: FinancialYear.create!(label: "Fringe 2026"))
      _budget, import = marketing_re_home(area: stale)

      re_home = import.re_homes.sole
      assert_equal "Cogito", re_home[:from_area_name]
      assert_equal "Fringe 2026", re_home[:from_area_scope]
      assert_equal "Cogito", re_home[:to_area_name]
      assert re_home[:to_area_is_new], "this year has no Cogito yet, so one is about to be created"
    end

    # The qualifications exist only for that collision: an ordinary re-home
    # must read exactly as it did before record identity replaced the name.
    test "an ordinary re-home qualifies neither side" do
      cogito = area_named("Cogito")
      improverts = area_named("Improverts")
      _budget, import = marketing_re_home(area: improverts, existing_areas: [ cogito, improverts ])

      re_home = import.re_homes.sole
      assert_nil re_home[:from_area_scope]
      assert_not re_home[:to_area_is_new]
    end

    # --- The owner sign-off gate ---------------------------------------------
    # Budget#owners resolves THROUGH the area, and OwnerReview.gate_applies? is
    # false with no owners — so a line landing in an ownerless area stops
    # needing endorsement. The area form and the budget form both warn about
    # this; the importer is the third way in, the only silent one, and the one
    # that moves many lines at once.

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

    test "a re-home into an existing area that names nobody reports it too" do
      _budget, import = marketing_re_home(existing_areas: [ area_named("Cogito") ])

      assert_not import.re_homes.sole[:to_area_has_owners]
    end

    # The warning is read AFTER this import's own owner column, which now feeds
    # the AREA: a sheet that names somebody for the area it is moving the line
    # into leaves the gate standing, so warning there would be false. Narrowed,
    # not closed — the two tests above still land here.
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
    # Unticking every re-home on a pure re-import used to mint the area anyway
    # — the exact orphan this bucket exists to prevent, reached by taking the
    # cautious option it offers.

    test "unticking the only re-home into a new area stops it being created" do
      _budget, import = marketing_re_home

      assert_equal [ "Cogito" ], import.area_creates.map { |a| a[:name] }
      assert_empty import.area_creates_for([])
      assert_equal [ "Cogito" ], import.area_creates_for(import.re_homes).map { |a| a[:name] }
    end

    test "an area a new line lands in is created however the re-homes are ticked" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t400
      TSV

      assert_equal [ "Cogito" ], import.area_creates_for([]).map { |a| a[:name] }
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

    # --- The sheet's owner column names the AREA ------------------------------
    # "Once there's an area the owner of a budget line is moot and we only look
    # at the area" — which is exactly what Budget#owners does. Phase 1 left the
    # sheet's named owner landing on rows nobody reads, so that owner got no
    # sign-off gate at all.

    test "a matched line in an area sends the sheet's owner to the AREA, not its own rows" do
      budget, alice, bob = props_in_area_owned_by_bob

      import = build_import(tsv("Props\t4000\tExpense\t1000\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice, bob ])

      assert_empty import.owner_syncs,
                   "Budget#owners reads through the area, so the line's own rows are moot"
      sync = import.area_owner_syncs.sole
      assert_equal budget.area.record_id, sync[:area_id]
      # Bob is nowhere on this sheet and must survive it: a spreadsheet has no
      # way to say "remove this owner", so a sync only ever adds.
      assert_equal [ alice.record_id, bob.record_id ].sort, sync[:owner_ids].sort
    end

    # --- What the preview's submit button counts ----------------------------
    # The button is disabled when nothing is going to happen, so a bucket the
    # count forgets cannot be applied AT ALL. That is how the owner column Task
    # 5 added became unreachable on the most likely sheet: the same file re-sent
    # with owners filled in and no figures changed.

    test "the button's count covers every kind of work an apply does" do
      arguments = DatabaseStore.instance_method(:import_budgets!).parameters
                               .filter_map { |kind, name| name if [ :key, :keyreq ].include?(kind) }
      # note and created_by name the revision log; they are not work.
      assert_equal (arguments - [ :note, :created_by ]).sort,
                   build_import(tsv("Props\t4000\tExpense\t1200\t\t")).apply_work.keys.sort
    end

    test "an owner-only sheet is something to import" do
      budget, alice, bob = props_in_area_owned_by_bob

      # An area that exists, a line already in it, the SAME figure: the only
      # thing this sheet does is give the area an owner.
      import = build_import(tsv("Props\t4000\tExpense\t1000\talice@example.com\t"),
                            existing_budgets: [ budget ], people: [ alice, bob ])

      assert_predicate import, :valid?
      work = import.apply_work.each_value.reject { |_, count| count.zero? }
      assert_equal [ [ "area owner update", 1 ] ], work
    end

    test "unticking every re-home drops the area nothing will land in from the count" do
      elsewhere = create_reimbursements_area(name: "Improverts", financial_year: @year,
                                             cost_centre: @cost_centre)
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1000, area: elsewhere,
                                            financial_year: @year, cost_centre: @cost_centre)
      sheet = [ [ "Area", "Area Budget", "Budget name", "Nominal code", "Type", "Amount" ].join("\t"),
                [ "Cogito", "", "Props", "4000", "Expense", "1000" ].join("\t") ].join("\n")

      import = build_import(sheet, existing_budgets: [ budget ], existing_areas: [ elsewhere ])

      ticked = import.apply_work.each_value.reject { |_, count| count.zero? }
      assert_equal [ [ "new area", 1 ], [ "moved line", 1 ] ], ticked
      # Apply passes the TICKED re-homes, and an area nothing lands in is never
      # created — so the label must not promise one either.
      assert_empty import.apply_work(re_homes: []).each_value.reject { |_, count| count.zero? }
    end

    test "an area owner sync converges: a re-import reports it once" do
      budget, alice, bob = props_in_area_owned_by_bob
      sheet = tsv("Props\t4000\tExpense\t1000\talice@example.com\t")

      first = build_import(sheet, existing_budgets: [ budget ], people: [ alice, bob ])
      assert_equal [ alice.record_id, bob.record_id ].sort,
                   first.area_owner_syncs.sole[:owner_ids].sort

      DatabaseStore.new.add_area_owners!(budget.area.record_id, [ alice.record_id ])

      second = build_import(sheet, existing_budgets: [ budget.reload ], people: [ alice, bob ])
      assert_empty second.area_owner_syncs, "the same sync must not be reported for ever"
    end

    # The sheet has ONE owner column per line, so three lines under one area can
    # name three people — and all three are meant. Any one owner satisfies the
    # gate, so the union is the forgiving direction: an extra owner can endorse,
    # a missing one strands the claim.
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
      assert_equal [ alice.record_id ], import.owner_syncs.sole[:owner_ids]
    end

    # A sheet naming only people the area already has is not a change. Reporting
    # one would put an "owners updated" line on every re-import for ever, and
    # hide the imports that really do hand a show a new signatory.
    test "a sheet naming a subset of an area's owners reports nothing" do
      budget, _alice, bob = props_in_area_owned_by_bob

      import = build_import(tsv("Props\t4000\tExpense\t1000\tbob@example.com\t"),
                            existing_budgets: [ budget ], people: [ bob ])

      assert_empty import.area_owner_syncs
    end

    # Resolved the same way #creates' area is: by NAME when this very import is
    # about to create it, so import_budgets! can swap in the new row's id inside
    # its transaction.
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

    # An unknown address is skipped, never invented as a Person — so it hands
    # the area nothing, and an area whose only named owner is stale still has
    # no signatory.
    test "an owner email that matched nobody adds nothing to the area" do
      import = build_import(<<~TSV, existing_areas: [ area_named("Cogito") ])
        Area\tBudget\tNominal code\tType\tAmount\tOwner emails
        Cogito\tCogito: Marketing\t432320\tExpense\t400\tgone@example.com
      TSV

      assert_empty import.area_owner_syncs
      assert_equal [ "gone@example.com" ], import.unknown_owner_emails
    end

    # A matched line with no area of its own, whose sheet names one, is written
    # BOTH places on purpose: the move only happens if the operator leaves the
    # re-home ticked, and this model can't know which way that tick went.
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
    # A named list, never a count: the union is forgiving, so a stale address on
    # one line would otherwise gain sign-off authority over a whole show with
    # nothing on screen to say so.

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

    # The whole cost of the blank-cell reading is that it can write to an area
    # nothing else on the page mentions — no re-home is reported for that line,
    # so Task 4's qualified label never appears. Areas are named per show and
    # shows recur, so the two Cogitos here are a real pair, and unqualified they
    # render as two identical lines with no way to tell which gains whom.
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
      # An xlsx cell really can contain a tab or a line break, and the preview
      # carries the sheet on as TSV in a hidden field — so without escaping,
      # one stray tab in a note shifts every later column when apply re-parses.
      file = xlsx_fixture(xlsx_sheet([ "Props", "4000", "Expense", "100", "", "one\ttwo\nthree" ]))
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

    # --- The sheet still writes the prefix the rename took off ----------------
    # AreaRename.strip! rewrote "Cogito: Marketing" to "Marketing", and the
    # committee's spreadsheet goes on saying "Cogito: Marketing" — through the
    # deploy window at least, and for as long as they re-send the file they
    # have. Matched on the whole name alone, every renamed line buckets as a
    # CREATE: on the live Fringe data that is 17 of 31 budgets duplicated in one
    # apply, each with a fresh initial_budget, the show's spend split across two
    # lines and the original reported absent.
    #
    # So a line whose sheet names an AREA is matched on that area plus its bare
    # name, in both spellings and both directions — the stored side is mid-rename
    # for the length of a deploy window, and a name can be re-prefixed by hand
    # long afterwards.

    # A show whose lines have been through the rename: the area holds the
    # grouping and its budgets are bare, while every sheet below still spells
    # the prefix out.
    def renamed_cogito(*names)
      area = area_named("Cogito")
      budgets = names.map do |name|
        create_reimbursements_budget(name: "Cogito: #{name}", area: area, initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
      end
      Reimbursements::AreaRename.strip!
      [ area, budgets.map(&:reload) ]
    end

    # A one-line sheet filing +name+ under +cell+, the shape every test in this
    # section needs and the one the two area columns actually matter for.
    def area_sheet(cell, name, amount: 500)
      <<~TSV
        Area\tBudget\tNominal code\tType\tAmount
        #{cell}\t#{name}\t432320\tExpense\t#{amount}
      TSV
    end

    # The case the whole rule exists for: the sheet the committee already has,
    # re-imported the day after the rename ships.
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

    # The other direction: this row has not been renamed yet (or somebody
    # re-prefixed it by hand) and the sheet has moved on to the bare name.
    test "a bare sheet name matches a stored line that still carries the prefix" do
      area = area_named("Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                            initial_budget: 400, financial_year: @year,
                                            cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: [ budget ], existing_areas: [ area ])

      assert_equal :revise, import.entries.sole.bucket
      assert_equal budget.record_id, import.entries.sole.budget.record_id
    end

    test "the whitespace the rename tolerated is the whitespace matching tolerates" do
      area = area_named("Improverts")
      budget = create_reimbursements_budget(name: "Retreat", area: area, initial_budget: 400,
                                            financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Improverts", "Improverts:  Retreat"),
                            existing_budgets: [ budget ], existing_areas: [ area ])

      assert_equal :revise, import.entries.sole.bucket
    end

    # The rename's fourth rule, stated for matching: only the line's OWN area's
    # name comes off, so another show's prefix is part of the name.
    test "a prefix that is not this line's area is not stripped" do
      area = area_named("Cogito")
      budget = create_reimbursements_budget(name: "Retreat", area: area, initial_budget: 400,
                                            financial_year: @year, cost_centre: @cost_centre)

      import = build_import(area_sheet("Cogito", "Improverts: Retreat"),
                            existing_budgets: [ budget ], existing_areas: [ area ])

      assert_equal :create, import.entries.sole.bucket
    end

    test "an area-less line matches exactly as it always did" do
      budget = create_reimbursements_budget(name: "Contingency", initial_budget: 400,
                                            financial_year: @year, cost_centre: @cost_centre)

      import = build_import(tsv("Contingency\t4000\tExpense\t500\t\t"),
                            existing_budgets: [ budget ])

      assert_equal :revise, import.entries.sole.bucket
    end

    # THE MOST LIKELY SHEET IN THE WORLD: the committee's untouched old file,
    # prefixed names and no Area column at all, re-sent after the rename. The
    # stored row knows its own area without being told, so it is findable under
    # both spellings and this file still revises rather than duplicating.
    test "the old sheet with no Area column still revises its renamed lines" do
      _area, budgets = renamed_cogito("Marketing", "Set")

      import = build_import(tsv("Cogito: Marketing\t432320\tExpense\t500\t\t",
                                "Cogito: Set\t432330\tExpense\t600\t\t"),
                            existing_budgets: budgets)

      assert_empty import.entries_in(:create)
      assert_equal budgets.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
      assert_empty import.absent_budgets
    end

    # The bare spelling of the same file, also with no Area column.
    test "a bare name with no Area column still matches a line that carries the prefix" do
      area = area_named("Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                            initial_budget: 400, financial_year: @year,
                                            cost_centre: @cost_centre)

      import = build_import(tsv("Marketing\t432320\tExpense\t500\t\t"),
                            existing_budgets: [ budget ])

      assert_equal :revise, import.entries.sole.bucket
    end

    # Carrying both spellings does not bend the rule: another line literally
    # named "Cogito: Marketing" collides with Cogito's own "Marketing", and the
    # import stops rather than picking one.
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

    # Two spellings of ONE line in one sheet get past the duplicate check, which
    # compares what the sheet typed. Applying both would write two forecasts to
    # one budget.
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
    # Two shows each running a "Marketing" line is what stripping the prefixes
    # leaves behind, and the bare name can no longer tell them apart. The area
    # can, which is why the key carries it — and where even that doesn't
    # separate them, the import stops and names the rows rather than picking
    # one, the rule the strict column matcher already sets.

    # Two shows each running a bare "Marketing" line, keyed by show. Improverts
    # is built FIRST on purpose: a fallback to the plain name would answer with
    # it, so a test asserting Cogito's line can only pass on the area key.
    def two_shows_running_marketing
      %w[Improverts Cogito].to_h do |show|
        area = area_named(show)
        [ show, create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 400,
                                             financial_year: @year, cost_centre: @cost_centre) ]
      end
    end

    def areas_named(shows) = shows.values.map(&:area)

    test "the sheet's area picks between two shows' lines of the same name" do
      shows = two_shows_running_marketing

      import = build_import(area_sheet("Cogito", "Cogito: Marketing"),
                            existing_budgets: shows.values, existing_areas: areas_named(shows))

      assert_equal shows["Cogito"].record_id, import.entries.sole.budget.record_id
      assert_equal [ shows["Improverts"].record_id ], import.absent_budgets.map(&:record_id)
    end

    # The bare spelling of the same sheet: the plain name answers to both shows
    # now, and the area is the only thing separating them.
    test "the area key beats a bare name both shows answer to" do
      shows = two_shows_running_marketing

      import = build_import(area_sheet("Cogito", "Marketing"),
                            existing_budgets: shows.values, existing_areas: areas_named(shows))

      assert_equal shows["Cogito"].record_id, import.entries.sole.budget.record_id
    end

    test "two stored lines of one name block a sheet that cannot separate them" do
      shows = two_shows_running_marketing

      import = build_import(tsv("Marketing\t4000\tExpense\t500\t\t"),
                            existing_budgets: shows.values)

      assert_not import.valid?
      assert_match(/matches more than one budget/, import.entries.sole.error)
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
      # Names the AREA too: the collision is two identical names, and
      # "Marketing" twice tells the operator nothing they can act on.
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
    # MICK'S RULING (2026-09-11): they are two lines. A Termtime overhead called
    # "Marketing" beside a show's is a real pair, and the committee may write
    # both. Phase 2a refused any sheet carrying both spellings — deliberately,
    # as a holding position, because a fix round was the wrong place to decide
    # what the committee is allowed to write.
    #
    # The AREA CELL is what disambiguates, and a row that names no area means
    # the line that is in no area. Where nothing can say which show a bare name
    # belongs to, the import still stops: that is the old sheet's shape, and
    # guessing there is how 17 of 31 live lines duplicated.

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

    # The row that must keep blocking: only area-bound lines answer to the name,
    # and the sheet does not say which show it meant.
    test "a bare name with no area cell still blocks when only area-bound lines could match" do
      shows = two_shows_running_marketing

      import = build_import(tsv("Marketing\t432320\tExpense\t500\t\t"),
                            existing_budgets: shows.values, existing_areas: areas_named(shows))

      assert_not import.valid?, "the sheet does not say which show this is"
      assert_match(/matches more than one budget/, import.entries.sole.error)
    end

    # Two loose lines of one name is reachable — budget names are not unique, and
    # 14 of the 31 live Fringe lines have no area — and the reading has nothing
    # to choose between them with. Neither lookup may guess.
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

    # ONE line written twice, which is not the pair the ruling legitimised: both
    # rows name Cogito's Marketing, one by the cell and one by the prefix. A
    # sheet mid-transition between the two spellings is the likeliest one the
    # committee sends, and with nothing stored yet it would otherwise create two
    # lines, each with its own agreed figure.
    test "an area cell and the same area's prefix are one line, not two" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
      TSV

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert_match(/named more than once in this sheet/, import.entries.first.error)
    end

    # N1: the normalisation has to reach CREATING, not only grouping. Created as
    # a loose line carrying the prefix, the next fully-converted sheet creates
    # "Marketing" inside Cogito and reports this one absent — two lines for one,
    # each with its own agreed figure, off the likeliest transitional sheet.
    test "a create adopts the area its own name names, and drops the prefix" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tSet\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
      TSV

      assert import.valid?, import.entries.filter_map(&:error).inspect
      assert_equal [ %w[Set Cogito], %w[Marketing Cogito] ],
                   import.creates.map { |create| [ create[:name], create[:area_name] ] }
    end

    # The same row's owner belongs to the AREA, since Budget#owners resolves
    # through it — written to the line's own rows it is one no sign-off gate
    # ever consults.
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

    # A row that MATCHED keeps its Area cell alone: moving a stored line into a
    # show on the strength of a prefix is a larger claim than naming a new one,
    # and Phase 2a pinned the out-of-scope reading this would quietly change.
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

    # N2: for a group the PREFIX named, "told apart by their area" invites an
    # Area cell that would change nothing — the rows already agree about it.
    test "the duplicate message does not suggest an Area cell the prefix already gave" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        \tCogito: Marketing\t432330\tExpense\t600
      TSV

      assert_match(/already names Cogito, so an Area cell would not tell them apart/,
                   import.entries.first.error)
      assert_no_match(/told apart by their area/, import.entries.first.error)
    end

    # Only an area THE SHEET NAMES reads as a prefix: with no Cogito row above
    # them, these are lines whose names happen to carry a colon, and the third
    # row is what makes that observable — read as a prefix, the last two rows
    # collapse onto one key (the colon's spacing is part of a NAME and not part
    # of an area plus a line) and the sheet would be refused.
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

    # N5: several declined namesakes, so the note reads as a list rather than
    # naming one line twice.
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

    # The reading is for a row that pointed at NO show. This one pointed at
    # Cogito and missed, so taking the line that is in no area would move it
    # into Cogito rather than revise the line the row meant.
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

    # Where every row already names an area (or none does), the area cell has
    # nothing left to add, so the instruction is the original one.
    test "two rows naming the same area and name are told to name it once" do
      import = build_import(<<~TSV)
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        Cogito\tMarketing\t432320\tExpense\t600
      TSV

      assert_not import.valid?
      assert_match(/Name it once/, import.entries.first.error)
      assert_no_match(/its own Area cell/, import.entries.first.error)
    end

    # It must not make two AREA-LESS rows equal to each other: their own names
    # are all they have to go on, and these are two different budgets.
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

    # Two shows' lines in one sheet are NOT duplicates — the area separates
    # them, and refusing here would block the state the rename leaves behind.
    test "the same bare name under two areas is two lines, not a duplicate" do
      shows = two_shows_running_marketing

      import = build_import(<<~TSV, existing_budgets: shows.values, existing_areas: areas_named(shows))
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tCogito: Marketing\t432320\tExpense\t500
        Improverts\tImproverts: Marketing\t432330\tExpense\t600
      TSV

      assert import.valid?, import.errors.inspect
      assert_equal shows.values.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
    end

    # The sheet Phase 2a is asking the committee to write: bare names, one per
    # show. A row that names an area is identified BY that area, so these are
    # two lines rather than one name typed twice.
    test "bare names under two areas are two lines, not a duplicate" do
      shows = two_shows_running_marketing

      import = build_import(<<~TSV, existing_budgets: shows.values, existing_areas: areas_named(shows))
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        Improverts\tMarketing\t432330\tExpense\t600
      TSV

      assert import.valid?, import.errors.inspect
      assert_equal shows.values.map(&:record_id).sort, import.revisions.map { |r| r[:budget_id] }.sort
    end

    # Same name, same area, still one line typed twice — and the message counts
    # them rather than listing one label twice, which is all it could say.
    test "the same bare name under one area is still a duplicate" do
      shows = two_shows_running_marketing

      import = build_import(<<~TSV, existing_budgets: shows.values, existing_areas: areas_named(shows))
        Area\tBudget\tNominal code\tType\tAmount
        Cogito\tMarketing\t432320\tExpense\t500
        Cogito\tMarketing\t432330\tExpense\t600
      TSV

      assert_not import.valid?
      assert_equal 2, import.entries_in(:invalid).size
      assert_match(/"Marketing" \(Cogito\), 2 times/, import.entries.first.error)
    end

    # The two halves of the name index are a PARTITION of .name_spellings, so
    # together they are still every spelling a line answered to before the
    # split. Losing one half reddens a dozen tests; losing a single spelling
    # under a degenerate name would be silent, and that line would simply stop
    # being findable by the sheet that names it.
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
    # DatabaseStore#in_year is lenient, so an unstamped legacy area sits in every
    # year's list beside a real one of the same name. Picking one silently moves
    # a line's spend into the wrong show's total and hands its sign-off gate to
    # that show's owners, which is what #re_homes does with the answer.

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
