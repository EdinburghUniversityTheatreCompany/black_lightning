# Area Grouping — Phase 2a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed areas from the committee's spreadsheet, and make the existing finance screens read them.

**Architecture:** Phase 1 built `Reimbursements::Area` and can only be populated by a one-off backfill or by hand. This plan teaches `Reimbursements::BudgetImport` to carry an area per line, an agreed total per area, and to target the area with the sheet's owner column — plus the rename that finally strips `Area: ` from the budget names, and the area rollup and export column that make the grouping visible.

**Tech Stack:** Rails 8.1, MySQL 8.4 (multi-database: `primary`, `queue`, `cache`), minitest with fixtures, ViewComponents, simple_form + `FormStyles`, Tailwind v4.

**Spec:** [docs/superpowers/specs/2026-09-10-area-grouping-design.md](../specs/2026-09-10-area-grouping-design.md) — read its "Open questions" section, all five now resolved with reasoning.

**Phase 2b (separate plan, after this):** `Reimbursements::NominalCode` + its maintenance on the cost centre edit page, and find-or-create of a budget line from a claim. Both depend on a code list that does not exist yet; nothing in this plan does.

## Global Constraints

- **Multi-database app.** `bin/rails db:rollback:primary STEP=n` — a bare `db:rollback` errors. **Run the rollback for every migration and confirm it reverses.** After a FAILED migration on MySQL, run `db:migrate:status` before rolling back: DDL can partially auto-commit, and Phase 1 saw a blind `STEP=1` revert an unrelated migration.
- **`strong_migrations` blocks `add_reference … foreign_key:` on a populated table.** Use the gem's own printed pattern: `add_reference` without `foreign_key:`, then `add_foreign_key` inside `safety_assured` with `execute "SET SESSION foreign_key_checks = 0"` before and `= 1` in an `ensure`. **`safety_assured` must wrap the `execute` calls too** — `execute` is independently flagged. Explicit `up`/`down`, never `change`.
- **Test and CI databases are schema-LOADED**, so a data migration never runs there. Anything a test needs, the test creates. A data migration's logic belongs in a service the tests can call.
- **`test/fixtures/reimbursements/cost_centres.yml` stays at ONE row.** A second centre comes from `create_second_reimbursements_cost_centre`; a second fixture row makes `CostCentre.default` resolve to whichever label `FixtureSet.identify` hashes lower.
- **No mocking library** — no mocha, no `minitest/mock`. Stub externals by toggling config.
- **Assert `errors[:field].present?`**, never Rails' default message string — validation messages are i18n-customised here.
- **Typed money goes through `Reimbursements::AmountParser`** and reaches the database as the parsed BigDecimal. AR casts a String to a decimal column with `to_d`, so a raw `"£1,200"` stores as **0**.
- **A form opened INSIDE a `CardComponent` renders its submit outside the `<form>`** and the button silently does nothing. The form wraps the card. **Every form gets a system test clicking the real button** — four defects across Phase 1 came from browsers posting different parameters than tests do.
- **A link inside a wizard's Turbo Frame needs `data: { turbo_frame: "_top" }`** unless its destination carries the same frame, or Turbo renders "Content missing".
- **Area figures are read off `store.areas`** (unscoped, preloading `budgets: [:expenses, :forecasts]`), never off `budget.area`, whose `budgets` collection is unloaded. Measured in Phase 1: 32→31 queries versus 10→36.
- **`remaining` and `unallocated` are nil, never zero, when nobody agreed a total.**
- **`Budget#owners` is `area ? area.owners : own_owners`.** The budget's own rows are KEPT so the Phase 1 backfill stays reversible, but do not apply when an area is present.
- **NEVER `git stash`** — `refs/stash` is shared by every worktree in this repo. Throwaway commit + `reset --soft` instead.
- **Commit with `--no-verify`**; `HK_SKIP_HOOK=1` does not suppress hk's repo-wide stash. Run `hk run check --from-ref <base> --to-ref HEAD` at the end instead (plain `hk run check` scans only the working diff and proves nothing).
- Serialize test runs behind `flock /tmp/bl-test.lock -c '<cmd>'`, echoing before the wait (600s no-output watchdog). **Stop `bin/dev` before system tests** — a running dev server fails ~57 unrelated ones.
- Strip `REIMBURSEMENTS_*` env vars before running the suite by hand.
- Every commit message ends with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Responsibility |
|---|---|
| `app/models/reimbursements/budget_import.rb` | the strict matcher, the two new columns, the re-home bucket, area-targeted owners |
| `app/views/admin/reimbursements/budget_imports/preview.html.erb` | the column mapping, the re-home bucket, the per-area owner set |
| `app/services/reimbursements/database_store.rb` | `import_budgets!` gains area creates, area totals and re-homes |
| `app/services/reimbursements/area_rename.rb` | the prefix strip, as a service so it can be tested |
| `db/migrate/*_strip_area_prefix_from_budget_names.rb` | calls that service; `down` reconstructs |
| `app/models/reimbursements/area_rollup.rb` | the overview's area subtotals, mirroring `NominalCodeRollup` |
| `app/services/reimbursements/exports/budgets.rb` | an appended `Area` column |

---

### Task 1: Port the strict column matcher to the budget import

**This task must come first.** The two columns Tasks 2–3 add would silently break the existing ones without it.

**Files:**
- Modify: `app/models/reimbursements/budget_import.rb:41-54` (`COLUMNS` → `FIELDS`), `:245-250` (`column`)
- Modify: `app/views/admin/reimbursements/budget_imports/preview.html.erb`
- Test: `test/models/reimbursements/budget_import_test.rb`, `test/functional/admin/reimbursements/budget_imports_controller_test.rb`

**Interfaces:**
- Produces: `BudgetImport::FIELDS` (a Hash of `field => { label:, exact: [], contains: [] }`), `#column_mapping` returning `{ field_label => header_or_nil }` for the preview.

**Why:** `COLUMNS[:name]` ends with the bare keyword `budget`, and `ImportParsing#find_column` falls back to "the first header CONTAINING all these words". So the header **`Area Budget`** — which Task 3 adds — resolves to the budget **name** column, and a sheet with both `Area` and `Area Budget` has two fields matching one header. `Reimbursements::ExpenseImport` was fixed for exactly this class in September 2026 after a `Payment reference` column answered to its dedupe key and an `Account number` column answered to its claim number; copy that fix rather than inventing one.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/budget_import_test.rb
test "an Area Budget column is never read as the budget name" do
  headers = "Area\tArea Budget\tBudget\tNominal code\tType\tAmount\tOwner emails\tNotes"
  row = "Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400\t\t"
  import = ::Reimbursements::BudgetImport.new(data: [ headers, row ].join("\n"),
                                              input_type: :paste,
                                              existing_budgets: [], people: [],
                                              financial_year: @year, cost_centre: @cost_centre)

  assert_equal "Cogito: Marketing", import.entries.first.row[:name],
               "the name must come from the Budget column, not from Area Budget"
end

test "two fields resolving to one column is refused, not guessed" do
  headers = "Budget name\tBudget\tNominal code\tType\tAmount"
  row = "Props\tProps\t4000\tExpense\t500"
  import = ::Reimbursements::BudgetImport.new(data: [ headers, row ].join("\n"),
                                              input_type: :paste,
                                              existing_budgets: [], people: [],
                                              financial_year: @year, cost_centre: @cost_centre)

  assert_not import.valid?
  assert_match(/same column/i, import.errors.join(" "))
end
```

(Check `BudgetImport.new`'s real keyword list before writing these — read its `initialize`. Match it exactly rather than the shape above.)

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb -n /Area_Budget|same_column/'`
Expected: FAIL — the first because `row[:name]` is `"1200"`, the second because nothing refuses ambiguity yet.

- [ ] **Step 3: Port the matcher**

Read `app/models/reimbursements/expense_import.rb`'s `FIELDS`, `match_header`, `ambiguous_columns` and `column_mapping` and bring the same three mechanisms across:
- `exact:` names matched WHOLE after normalisation (`value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip`);
- `contains:` phrases matched as substrings, **multi-word only** — a bare word is never a substring hint;
- two fields resolving to the same header is a blocking error naming both.

Keep every heading the current `COLUMNS` accepts, so no existing sheet stops working: `Budget name`, `Name`, `Line`, `Category`, `Budget`, `Nominal code`, `Nominal`, `Code`, `Budget type`, `Type`, `Amount`, `Initial budget`, `Forecast`, `Total`, `Owner emails`, `Owner email`, `Owners`, `Owner`, `Notes`, `Description`, `Comment`. Move each into `exact:`; put only the genuinely multi-word ones in `contains:`.

**Do not touch `ImportParsing#find_column`** — the membership and user imports still use it, and their sheets are flat enough for it.

- [ ] **Step 4: State the mapping in the preview**

Render `#column_mapping` as a `<details>` table ("Budget → Budget name", "Area → not in this sheet"), the way `expense_imports/preview.html.erb` does. This is what makes any remaining mis-mapping visible rather than silent, and it is worth more than the keyword tuning.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb test/functional/admin/reimbursements/budget_imports_controller_test.rb'`
Expected: PASS, both files whole. Every pre-existing budget-import test must still pass unmodified — if one needs changing, that is a heading the port dropped.

- [ ] **Step 6: Commit**

```bash
git add app/models/reimbursements/budget_import.rb app/views/admin/reimbursements/budget_imports/preview.html.erb test/
git commit --no-verify -m "refactor(reimbursements): the budget import matches columns strictly

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The sheet names an area per line

**Files:**
- Modify: `app/models/reimbursements/budget_import.rb` (`FIELDS`, `TSV_HEADERS`, `Entry`, `entry_for`, `creates`), `app/services/reimbursements/database_store.rb:299` (`import_budgets!`)
- Modify: `app/views/admin/reimbursements/budget_imports/preview.html.erb`, `apply.html.erb`
- Test: `test/models/reimbursements/budget_import_test.rb`, `test/services/reimbursements/database_store_test.rb`

**Interfaces:**
- Consumes: `FIELDS` and `#column_mapping` (Task 1).
- Produces: `Entry#area_name` (String or nil); `BudgetImport#area_creates` returning `[{ name:, cost_centre:, financial_year: }]` for areas the sheet names that do not exist; `import_budgets!` gaining `area_creates:` and each `creates` entry gaining `area_name:`.

**The matching rule:** an area is matched **by name within one (financial year, cost centre)** — the same rule a budget line uses, and the same rule `AreaBackfill` used. A new area is created when the sheet names one that does not exist. **Areas are never deleted by an import**, for the reason `absent_budgets` is reported and never deleted: a show's claims and history hang off its lines.

- [ ] **Step 1: Write the failing test**

```ruby
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
  import = build_import(<<~TSV)
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
```

Add a `build_import` helper to that test file if one does not exist, so the six tasks below do not each rebuild the constructor call.

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb -n /area/'`
Expected: FAIL — `NoMethodError: undefined method 'area_creates'`.

- [ ] **Step 3: Implement**

- Add `area: { label: "Area", exact: ["area"], contains: ["area name"] }` to `FIELDS`. **Not `contains: ["area"]`** — Task 3's `Area Budget` header contains it, and Task 1's ambiguity check would then refuse every sheet carrying both.
- Add `"Area"` to `TSV_HEADERS` as the first column, and to the downloadable template.
- Add `:area_name` to `Entry` and set it in `entry_for`.
- `#area_creates` returns the distinct area names the sheet uses that are not already in `existing_areas` (a new constructor keyword, passed `store.areas_for_year` from the controller).
- `#creates` gains `area_id:` resolved from the existing areas; for an area this import is about to create, the store resolves it after creation — pass `area_name:` through and let `import_budgets!` map it.
- `import_budgets!` creates the areas **first**, inside its existing transaction, then resolves each create's `area_name:` to the new id.

- [ ] **Step 4: Show it in the preview and the apply summary**

The preview states the areas that will be created, as it already does for budget lines. The apply summary counts them.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb test/services/reimbursements/database_store_test.rb'`
Expected: PASS, both whole.

- [ ] **Step 6: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): the budget sheet names an area per line

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The sheet carries the area's agreed total

**Files:**
- Modify: `app/models/reimbursements/budget_import.rb`, `app/services/reimbursements/database_store.rb`
- Test: `test/models/reimbursements/budget_import_test.rb`

**Interfaces:**
- Produces: `#area_creates` entries gaining `initial_budget:`; `#area_total_conflicts` returning `[{ area_name:, values: [] }]`.

**The rules** (spec, resolved 2026-09-10):
- The column repeats down the rows of an area, because the sheet has one row per budget line.
- **Two different values for one area is a BLOCKING error**, not last-one-wins — consistent with an unreadable amount stopping the whole import.
- **Write-once on create**, like a budget's `initial_budget`, so a re-import logs a revision rather than rewriting the figure the committee agreed. (An area revision is a `BudgetForecast` with `area_id` set — Phase 1 built that.)

- [ ] **Step 1: Write the failing test**

```ruby
test "the area's total is read once from the repeated column" do
  import = build_import(<<~TSV)
    Area\tArea Budget\tBudget\tNominal code\tType\tAmount
    Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400
    Cogito\t1200\tCogito: Other\t432320\tExpense\t800
  TSV

  assert_equal 1, import.area_creates.size
  assert_equal 1200, import.area_creates.first[:initial_budget]
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb -n /total|1,200/'`
Expected: FAIL — `area_creates` carries no `initial_budget`.

- [ ] **Step 3: Implement**

- `area_budget: { label: "Area Budget", exact: ["area budget", "area total"], contains: ["area budget", "area total"] }` in `FIELDS`. Both multi-word, so Task 1's rule is satisfied and neither collides with `Area` or `Budget`.
- `"Area Budget"` into `TSV_HEADERS`, second.
- Parse through `Reimbursements::AmountParser.parse` and carry the **BigDecimal**, never the raw cell.
- `#area_total_conflicts` groups the non-blank parsed values per area name and reports any with more than one distinct value; `#valid?` fails when it is non-empty, and the message names the area and the values.
- Write it only on create. A named area that already exists keeps its figure.

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb'`
Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): the budget sheet carries an area's agreed total

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: A sheet that disagrees with a hand-moved line reports a re-home

**Files:**
- Modify: `app/models/reimbursements/budget_import.rb`, `app/views/admin/reimbursements/budget_imports/preview.html.erb`, `app/controllers/admin/reimbursements/budget_imports_controller.rb`, `app/services/reimbursements/database_store.rb`
- Test: `test/models/reimbursements/budget_import_test.rb`, `test/functional/admin/reimbursements/budget_imports_controller_test.rb`

**Interfaces:**
- Produces: `#re_homes` returning `[{ budget_id:, from_area_name:, to_area_name:, key: }]`; `import_budgets!` gaining `re_homes:`.

**Why it is reported and not applied silently** (spec): somebody moved that budget on purpose through the area form or the budget form's picker. The importer's temperament is already this — `absent_budgets` are reported and never deleted, an unplaced line is adopted rather than quietly shared. So a re-home is **its own bucket, ticked by default**, like Reconcile's offsetting pairs, and unticking it leaves the hand-made grouping alone.

**Key the checkbox by budget id**, not by row position: a re-import with the rows reordered must not apply a tick to a different line. (Reconcile keys by row content *plus an occurrence index* because its rows have no id; here there is one, so use it.)

- [ ] **Step 1: Write the failing test**

```ruby
test "a sheet naming a different area than the budget currently has reports a re-home" do
  cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
  improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre, financial_year: @year)
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: improverts,
                                        cost_centre: @cost_centre, financial_year: @year)

  import = build_import(<<~TSV, existing_budgets: [ budget ], existing_areas: [ cogito, improverts ])
    Area\tBudget\tNominal code\tType\tAmount
    Cogito\tCogito: Marketing\t432320\tExpense\t400
  TSV

  re_home = import.re_homes.sole
  assert_equal budget.record_id, re_home[:budget_id]
  assert_equal "Improverts", re_home[:from_area_name]
  assert_equal "Cogito", re_home[:to_area_name]
end

test "a line already in the area the sheet names reports no re-home" do
  cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: cogito,
                                        cost_centre: @cost_centre, financial_year: @year)

  import = build_import(<<~TSV, existing_budgets: [ budget ], existing_areas: [ cogito ])
    Area\tBudget\tNominal code\tType\tAmount
    Cogito\tCogito: Marketing\t432320\tExpense\t400
  TSV

  assert_empty import.re_homes
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb -n /re.home/'`
Expected: FAIL — `undefined method 're_homes'`.

- [ ] **Step 3: Implement**

`#re_homes` covers `entries_in(:revise) + entries_in(:unchanged)` — a matched line is matched whether or not its figure moved, exactly as `#adoptions` and `#owner_syncs` already handle. Skip an entry whose budget has no area **and** whose sheet names none. A budget with an area the sheet leaves blank is **not** a re-home to nowhere — a blank cell means "the sheet says nothing", the same reading `bucket_for` gives a blank amount.

- [ ] **Step 4: Render the bucket and carry the ticks**

A ticked checkbox per re-home in the preview, keyed by budget id, stating "Cogito: Marketing — Improverts → Cogito". Apply reads back the ticked ids. **An unticked or unmatched key means leave it alone** — the safe direction, matching Reconcile's rule that a key which fails to match on apply reads as unticked.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb test/functional/admin/reimbursements/budget_imports_controller_test.rb'`
Expected: PASS, both whole.

- [ ] **Step 6: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): a sheet that re-homes a line says so rather than doing it

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The sheet's owner column names the AREA when a line has one

**Files:**
- Modify: `app/models/reimbursements/budget_import.rb:155` (`owner_syncs`), `app/services/reimbursements/database_store.rb`
- Modify: `app/views/admin/reimbursements/budget_imports/preview.html.erb`
- Test: `test/models/reimbursements/budget_import_test.rb`

**Interfaces:**
- Produces: `#area_owner_syncs` returning `[{ area_id:, owner_ids: }]`; `#owner_syncs` narrowed to area-less budgets; `import_budgets!` gaining `area_owner_syncs:`.

**Why** (spec, Mick 2026-09-10): "once there's an area the owner of a budget line is moot and we only look at the area" — which is exactly what `Budget#owners` does. Phase 1 left this half-fixed: the importer's comparison was corrected to read the rows it writes, so it converges, but the sheet's named owner still lands on rows nobody reads, and that owner gets no sign-off gate.

**The union rule:** the sheet has one owner column per LINE, so three lines under one area can name three people. The area's owners become the **union**. That is what `AreaBackfill#seed_owners!` already did, and it is the forgiving direction — any one owner satisfies the gate, so an extra owner can endorse while a missing one strands the claim.

**Because the union is forgiving, the preview must SHOW the resulting owner set per area**, not merely count syncs: a stale name on one line otherwise gains sign-off authority over a whole show invisibly.

- [ ] **Step 1: Write the failing test**

```ruby
test "an area's owners are the union of what its lines name" do
  area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
  alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
  bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
  marketing = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                           cost_centre: @cost_centre, financial_year: @year)
  other = create_reimbursements_budget(name: "Cogito: Other", area: area,
                                       cost_centre: @cost_centre, financial_year: @year)

  import = build_import(<<~TSV, existing_budgets: [ marketing, other ], existing_areas: [ area ],
                                people: [ alice, bob ])
    Area\tBudget\tNominal code\tType\tAmount\tOwner emails
    Cogito\tCogito: Marketing\t432320\tExpense\t400\talice@example.com
    Cogito\tCogito: Other\t432320\tExpense\t800\tbob@example.com
  TSV

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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb -n /union|area.less line still/'`
Expected: FAIL — `undefined method 'area_owner_syncs'`.

- [ ] **Step 3: Implement**

- `#area_owner_syncs` groups the matched entries by resolved area and unions their `owner_ids`, comparing against `area.owner_ids` so an unchanged set reports nothing.
- `#owner_syncs` filters to entries whose budget has **no** area, and keeps comparing `budget.own_owners.map(&:record_id)` — the rows it writes.
- `import_budgets!` calls `sync_area_owners!` for each, inside the existing transaction.
- **`resolve_owners`' existing rule is unchanged**: no `Person` is ever created from a bare email; an unknown address warns and is listed, and the preview links to `/admin/reimbursements/people/new`.

- [ ] **Step 4: Show the resulting owner set per area in the preview**

Not a count. Name the people each area will end up with, so a stale address is visible before apply.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_import_test.rb test/services/reimbursements/database_store_test.rb'`
Expected: PASS, both whole.

- [ ] **Step 6: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): the sheet's owner column names the area

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Strip the `Area: ` prefix from budget names

**Files:**
- Create: `app/services/reimbursements/area_rename.rb`
- Create: `db/migrate/20260912100000_strip_area_prefix_from_budget_names.rb`
- Test: `test/models/reimbursements/area_rename_test.rb`

**Interfaces:**
- Produces: `Reimbursements::AreaRename.strip!` and `.restore!`.

**Why a service, not migration code:** test and CI databases are schema-loaded, so a data migration never runs there and could never be tested. Phase 1's `AreaBackfill` is the pattern.

**The interaction with Phase 1's backfill, which is deliberate and must be preserved:** `BackfillReimbursementsAreas#down` refuses when "an Area's name is not reproducible as the colon-prefix of at least one of its own budgets". Stripping the prefix trips exactly that — correctly, because once stripped the area's name is the only place the grouping lives. **The chain still reverses in order**: this migration's `down` calls `restore!`, reconstructing `"#{area.name}: #{budget.name}"`, after which the backfill's guard passes again. Verify that end to end in Step 5.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/area_rename_test.rb
test "strips the area's name and the colon from its budgets" do
  area = create_reimbursements_area(name: "Cogito")
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

  Reimbursements::AreaRename.strip!

  assert_equal "Marketing", budget.reload.name
end

test "tolerates the extra whitespace the backfill tolerated" do
  area = create_reimbursements_area(name: "Improverts")
  budget = create_reimbursements_budget(name: "Improverts:  Retreat", area: area)

  Reimbursements::AreaRename.strip!

  assert_equal "Retreat", budget.reload.name
end

test "leaves an area-less budget alone" do
  budget = create_reimbursements_budget(name: "Contingency")
  Reimbursements::AreaRename.strip!
  assert_equal "Contingency", budget.reload.name
end

test "leaves a name that does not start with its own area's name alone" do
  area = create_reimbursements_area(name: "Cogito")
  budget = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

  Reimbursements::AreaRename.strip!

  assert_equal "Rehearsal room hire", budget.reload.name,
               "someone renamed this by hand; that is not this migration's to rewrite"
end

test "restore! puts the prefix back" do
  area = create_reimbursements_area(name: "Cogito")
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

  Reimbursements::AreaRename.strip!
  Reimbursements::AreaRename.restore!

  assert_equal "Cogito: Marketing", budget.reload.name
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_rename_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::AreaRename`.

- [ ] **Step 3: Implement the service and the migration**

`strip!` walks budgets with an area whose name matches `/\A#{Regexp.escape(area.name)}\s*:\s*(?<rest>.+)\z/` and writes `rest`. `restore!` writes `"#{area.name}: #{name}"` for a budget with an area whose name does not already start with it. Both with `update_column` — a bookkeeping rewrite must not be vetoed by an unrelated validation, and must not fire `inherit_area_scoping` on rows it is not there to stamp.

The migration is `up { AreaRename.strip! }` / `down { AreaRename.restore! }`.

- [ ] **Step 4: Prove the two migrations still reverse together**

```bash
bin/rails db:migrate
bin/rails db:rollback:primary STEP=2   # rename, then backfill
bin/rails db:migrate
```
Expected: both roll back cleanly. **If the backfill's `down` refuses here, the rename's `restore!` did not reconstruct every name** — that is the bug, not the guard.

- [ ] **Step 5: Commit**

```bash
git add app/services/reimbursements/area_rename.rb db/migrate db/schema.rb test/models/reimbursements/area_rename_test.rb
git commit --no-verify -m "feat(reimbursements): a line in an area drops the prefix from its name

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The overview gains an area rollup

**Files:**
- Create: `app/models/reimbursements/area_rollup.rb`
- Modify: `app/controllers/admin/reimbursements/budgets_controller.rb` (`overview`), `app/views/admin/reimbursements/budgets/overview.html.erb`
- Test: `test/models/reimbursements/area_rollup_test.rb`, `test/functional/admin/reimbursements/budgets_controller_test.rb`

**Interfaces:**
- Produces: `AreaRollup` mirroring `NominalCodeRollup`'s shape — `Struct.new(:area, :budgets, :budget_type)` with `#initial`, `#projected`, `#committed`, `#pipeline`, `#paid_portal`, `#eusa_actual` and `#by_type`.

**Two rules carried from `NominalCodeRollup`, both load-bearing:**
- **Expense and Income budgets are never totalled together** — £10k spend + £8k income is not £18k of anything. Every total comes through `#by_type`.
- **`expected_outturn` is nil for an Income budget** and renders blank.

**Read the figures off `store.areas`**, which preloads `budgets: [:expenses, :forecasts]` — never off `budget.area`.

- [ ] **Step 1: Write the failing test**

```ruby
test "an area rollup never totals Expense and Income together" do
  area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
  create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 400,
                               budget_type: "Expense")
  create_reimbursements_budget(name: "Ticket income", area: area, initial_budget: 800,
                               budget_type: "Income")

  rollup = Reimbursements::AreaRollup.new(area: area, budgets: area.budgets)

  assert_equal %w[Expense Income].sort, rollup.by_type.map(&:budget_type).sort
  assert_equal 400, rollup.by_type.find { |r| r.budget_type == "Expense" }.initial
  assert_equal 800, rollup.by_type.find { |r| r.budget_type == "Income" }.initial
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_rollup_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::AreaRollup`.

- [ ] **Step 3: Implement**

Read `app/models/reimbursements/nominal_code_rollup.rb` and mirror it, including `sum_of` and the `by_type` re-group. The area rollup additionally exposes the area's **own** agreed total, so the screen can show the committee's figure beside the sum of its lines — that difference is `Area#unallocated`, and it renders as "not yet allocated", **never as money spare**.

- [ ] **Step 4: Render it beside the nominal-code rollup**

A second card on `overview.html.erb`. The existing nominal-code card is unchanged — the two answer different questions (EUSA's axis and Bedlam's), and CLAUDE.md says the unattributed-actuals card is what stops unlinked spend disappearing, so do not disturb either.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_rollup_test.rb test/functional/admin/reimbursements/budgets_controller_test.rb'`
Expected: PASS, both whole.

- [ ] **Step 6: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): the overview totals by area as well as by code

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: An `Area` column in the exports

**Files:**
- Modify: `app/services/reimbursements/exports/budgets.rb` (`HEADERS`, `#row`), `app/services/reimbursements/exports/expenses.rb`
- Test: `test/services/reimbursements/exports/*_test.rb`

**The conventions, from CLAUDE.md:** one exporter per resource, each owning its `HEADERS` and a private `#row` **once** — that single definition drives both the per-view CSV and the workbook sheet, so add the column in the exporter and nowhere else. **Append** it, so a saved formula keeps pointing at the same column. Amounts stay numeric with no "£", dates are ISO 8601 with blanks left empty, and every cell goes through `Reimbursements::CellSanitizer`.

- [ ] **Step 1: Write the failing test**

```ruby
test "the budgets export names each line's area, and leaves it blank for an area-less line" do
  area = create_reimbursements_area(name: "Cogito")
  in_area = create_reimbursements_budget(name: "Marketing", area: area)
  loose = create_reimbursements_budget(name: "Contingency")

  rows = Reimbursements::Exports::Budgets.new(store: store).rows([ in_area, loose ])

  assert_equal "Area", Reimbursements::Exports::Budgets::HEADERS.last
  assert_equal "Cogito", rows.first.last
  assert_equal "", rows.second.last
end
```

(Read the exporter's real constructor and row API before writing this — `Exports::Base` defines it; match it exactly.)

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/exports/'`
Expected: FAIL — the header is not `"Area"`.

- [ ] **Step 3: Implement**

Append `"Area"` to `HEADERS` and `budget.area&.name.to_s` to `#row`. The expenses exporter resolves it through the claim's budget. **Do not add it to `Exports::People`** — a payee has no area, the same reason it carries no cost centre.

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/'`
Expected: PASS, the whole directory, including the workbook test.

- [ ] **Step 5: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): every export that can name an area carries it

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Close out Phase 2a

- [ ] **Step 1: Both suites**

```bash
docker start mysql8
ss -ltn | grep -E ":(3000|3036)"   # stop bin/dev first if this prints anything
flock /tmp/bl-test.lock -c 'bin/rails test'
flock /tmp/bl-test.lock -c 'bin/rails test:system'
```
Paste the real counts.

- [ ] **Step 2: The CI-equivalent gate**

```bash
hk run check --from-ref <base-sha> --to-ref HEAD
```
If `herb` fails, re-run it on an idle machine before believing it — its parser has a 1000ms timeout and reports a bogus ERB error under load.

- [ ] **Step 3: Drive the real wizard**

Start `bin/dev` (the worktree has its own ports from `.worktree-isolate.conf`), paste a sheet carrying `Area`, `Area Budget` and a re-home, and confirm the preview states the column mapping, the areas to be created, the re-home bucket and each area's resulting owner set. Screenshot it. **Stop `bin/dev` before system tests.**

- [ ] **Step 4: CLAUDE.md, traps only**

Terse, no feature narration — the user cut a 31-line section to 12 once and a 49-line one to 37. Worth recording: that the budget import now matches columns strictly and why (`Area Budget` would otherwise read as the budget name); that the sheet's owner column targets the area and the union rule; that a re-home is reported and ticked, never silent; and that the rename trips the Phase 1 backfill's `down` guard on purpose, the chain reversing only because `restore!` reconstructs the prefix.

- [ ] **Step 5: Comment pass**

Run `dev-hooks:compress-comments` over `git diff <base>..HEAD`. A comment survives only if it states something the code cannot show. Verify the pass is comment-only.

- [ ] **Step 6: Commit and report**

Report the counts, every decision the plan left open and what you chose, and the migration awaiting the user's approval.
