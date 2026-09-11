# Area Grouping — Phase 2b Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a cost centre a maintained list of nominal codes, let a claim find-or-create the budget line it belongs to, and close the five debts Phase 2a knowingly left behind.

**Architecture:** `nominal_code` is a free-text string on `reimbursements_budgets` and `reimbursements_eusa_actuals` today, so nothing validates it and nothing lists it. Phase 2b introduces `Reimbursements::NominalCode` — rows owned by a cost centre and maintained by that centre's finance admin on the Settings page that already edits cost centres — and uses it to make a budget line find-or-createable from a claim, which is Option D's stated end state: a budget is found-or-created per `(area, code)`. The free-text column stays as the stored value; the model is the allow-list beside it, the same shape as `Expense::FOREIGN_CURRENCIES` being a fixed list rather than free text.

**Tech Stack:** Rails 8.1, MySQL 8.4 (multi-database: `primary`, `queue`, `cache`), minitest with fixtures, ViewComponents, simple_form + `FormStyles`, Tailwind v4, Stimulus, Vite.

**Spec:** [docs/superpowers/specs/2026-09-10-area-grouping-design.md](../specs/2026-09-10-area-grouping-design.md) — Phase 2b implements its "nominal code list lives on the cost centre edit page, owned by that centre's finance admin" resolution and the find-or-create half of Option D.

**Phase 2a shipped and merged at `f058541e`** (36 commits). Its execution ledger, every ruling and all thirteen reviews are at `.superpowers/sdd/2026-09-10-area-grouping-phase-2a/`. **Read `final-review.md` and `final-rereview.md` before Task 5** — the two Criticals they found are the reason Task 5 exists.

## Global Constraints

- **Multi-database app.** `bin/rails db:rollback:primary STEP=n` — a bare `db:rollback` errors. **Run the rollback for every migration and confirm it reverses.** After a FAILED migration on MySQL run `db:migrate:status` before rolling back: DDL partially auto-commits, and a blind `STEP=1` once reverted an unrelated migration.
- **`strong_migrations` blocks `add_reference … foreign_key:` on a populated table.** Use the gem's printed pattern: `add_reference` without `foreign_key:`, then `add_foreign_key` inside `safety_assured` with `execute "SET SESSION foreign_key_checks = 0"` before and `= 1` in an `ensure`. **`safety_assured` must wrap the `execute` calls too.** Explicit `up`/`down`, never `change`.
- **Test and CI databases are schema-LOADED**, so a data migration never runs there. Anything a test needs, the test creates; a data migration's logic belongs in a service the tests can call (`AreaBackfill` and `AreaRename` are the pattern).
- **`test/fixtures/reimbursements/cost_centres.yml` stays at ONE row.** A second centre comes from `create_second_reimbursements_cost_centre`; a second fixture row makes `CostCentre.default` resolve to whichever label `FixtureSet.identify` hashes lower.
- **No mocking library** — no mocha, no `minitest/mock`. Seed with the `create_reimbursements_*` helpers. Stub externals by toggling config.
- **Assert `errors[:field].present?`**, never Rails' default message string — validation messages are i18n-customised here.
- **Typed money goes through `Reimbursements::AmountParser`** and reaches the database as the parsed BigDecimal. AR casts a String to a decimal column with `to_d`, so a raw `"£1,200"` stores as **0**.
- **A form opened INSIDE a `CardComponent` renders its submit outside the `<form>`** and the button silently does nothing. **Every form gets a browser test clicking the real control** — five defects across Phases 1 and 2a came from browsers posting different parameters than request tests do.
- **A link inside a wizard's Turbo Frame needs `data: { turbo_frame: "_top" }`**, or Turbo renders "Content missing".
- **A budget is named to a human through `Budget#display_name`** (`"Cogito — Marketing"`), never `budget.name`. Names are legitimately non-unique since the Phase 2a rename — live data carries 3× `Marketing` on one nominal code. The bare name is correct **only** where the area is already beside it: a rowgroup heading, the overview's area card, an export's own Area column, the name field on the budget form.
- **`Budget#owners` is `area ? area.owners : own_owners`.** Ownership is EDITED on the area; every writer must write `own_owners` or `area_owners`, never `owner_ids`, and **a blank list is the dangerous one** — `where.not(person_id: [])` compiles to `WHERE 1=1`.
- **Area figures are read off `store.areas`** (unscoped, preloading `budgets: [:expenses, :forecasts]`), never off `budget.area`, whose `budgets` collection is unloaded. Measured: 32→31 queries versus 10→36.
- **`remaining` and `unallocated` are nil, never zero**, when nobody agreed a total.
- **Expense and Income budgets are never totalled together**, and `expected_outturn` is nil for an Income budget.
- **Everything goes through `Reimbursements.build_store`.** Never hit AR models directly from a controller or job. The store seam takes `financial_year:` AND `cost_centre:`; a fake that ignores scoping is written `->(**) { fake }`.
- **NEVER `git stash`** — `refs/stash` is shared by every worktree in this repo and by other live sessions. Throwaway commit + `reset --soft`.
- **Commit with `--no-verify`**; `HK_SKIP_HOOK=1` does not suppress hk's repo-wide stash. Run `hk run check --from-ref <base> --to-ref HEAD` at the end — plain `hk run check` scans only the working diff and proves nothing.
- **Commit BEFORE mutating** anything to verify a test: a `git checkout <file>` used to revert a mutation destroys an uncommitted fix in the same file.
- **Apply mutations ONE AT A TIME.** Two applied together have already cancelled and reported a false green on this work.
- Serialize test runs behind `flock /tmp/bl-test.lock -c '<cmd>'`, echoing before the wait (600s no-output watchdog). Strip `REIMBURSEMENTS_*` env vars (`env -u …`). **`bin/rails test` does NOT run system tests** — `bin/rails test:system` is separate, and Phase 2a shipped a RED system test that survived two tasks because of exactly that.
- **jscpd gates duplication at threshold 0** (minTokens 70) in hk and CI. Extract; you cannot copy.
- **A comment survives only if it states something the code cannot show.** Phase 2a's comment pass cut 1017 → 849 added lines; do not undo it.
- Every commit message ends with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Responsibility |
|---|---|
| `app/models/reimbursements/nominal_code.rb` | a code + label owned by a cost centre; uniqueness within the centre |
| `db/migrate/*_create_reimbursements_nominal_codes.rb` | the table and its FK |
| `app/services/reimbursements/nominal_code_seed.rb` | first population from the codes budgets already carry — a service, because test DBs are schema-loaded |
| `app/controllers/admin/reimbursements/nominal_codes_controller.rb` | maintenance, nested under the cost centre it belongs to |
| `app/views/admin/reimbursements/settings/_nominal_codes.html.erb` | the list + add/remove, on the Settings page that already edits cost centres |
| `app/services/reimbursements/budget_finder.rb` | find-or-create a budget for `(area, code)` |
| `app/controllers/admin/reimbursements/budgets_controller.rb` | the owner-discard fix (Phase 2a M8) |
| `db/migrate/*_drop_name_before_area_rename.rb` | closes the rename's rollback window, deliberately and last |

---

### Task 1: The `NominalCode` model and its table

**Files:**
- Create: `app/models/reimbursements/nominal_code.rb`, `db/migrate/<stamp>_create_reimbursements_nominal_codes.rb`
- Test: `test/models/reimbursements/nominal_code_test.rb`
- Modify: `test/support/reimbursements_test_helpers.rb` (a `create_reimbursements_nominal_code` helper)

**Interfaces:**
- Produces: `Reimbursements::NominalCode` with `code`, `label`, `cost_centre`, `active`; `.for_cost_centre(cc)` ordered by code.

**Why a row per cost centre and not a global list:** the two centres are different EUSA accounts with their own charts of accounts, and the spec puts maintenance in the hands of *that centre's* finance admin. A global list would let Fringe's admin retire a code Bedlam books against.

**`code` is a STRING and stays one.** Nominal codes are zero-padded (`041000`), and `Base#add_sheet` already pins String cells to Axlsx `:string` precisely because a numeric-looking identifier is coerced to `41000` otherwise. An integer column would lose the padding at the source.

- [ ] **Step 1: Write the failing test**

```ruby
test "a code is unique within its cost centre but not across centres" do
  fringe = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  termtime = create_second_reimbursements_cost_centre

  create_reimbursements_nominal_code(code: "432320", cost_centre: fringe)
  dupe = Reimbursements::NominalCode.new(code: "432320", cost_centre: fringe, label: "Marketing")
  assert_not dupe.valid?
  assert dupe.errors[:code].present?

  other = Reimbursements::NominalCode.new(code: "432320", cost_centre: termtime, label: "Marketing")
  assert other.valid?, "the same code in another centre is a different account"
end

test "a zero-padded code keeps its padding" do
  code = create_reimbursements_nominal_code(code: "041000")
  assert_equal "041000", code.reload.code
end

test "code and label must both be present" do
  blank = Reimbursements::NominalCode.new(cost_centre: create_reimbursements_cost_centre)
  assert_not blank.valid?
  assert blank.errors[:code].present?
  assert blank.errors[:label].present?
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/nominal_code_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::NominalCode`.

- [ ] **Step 3: Write the migration**

`reimbursements_cost_centres` is populated, so the FK follows the gem's printed pattern:

```ruby
class CreateReimbursementsNominalCodes < ActiveRecord::Migration[8.1]
  def up
    create_table :reimbursements_nominal_codes do |t|
      t.string :code, null: false
      t.string :label, null: false
      t.boolean :active, null: false, default: true
      t.bigint :cost_centre_id, null: false
      t.timestamps
      t.index %i[cost_centre_id code], unique: true,
              name: "index_reimbursements_nominal_codes_on_centre_and_code"
    end

    safety_assured do
      execute "SET SESSION foreign_key_checks = 0"
      add_foreign_key :reimbursements_nominal_codes, :reimbursements_cost_centres,
                      column: :cost_centre_id
    ensure
      execute "SET SESSION foreign_key_checks = 1"
    end
  end

  def down
    drop_table :reimbursements_nominal_codes
  end
end
```

**Declare the index INSIDE `create_table`** — a standalone `add_index` beside an FK makes `create_table` irreversible, which this repo has already been bitten by.

- [ ] **Step 4: Write the model**

Uniqueness is `scope: :cost_centre_id`, `case_sensitive: false` (the column is `utf8mb4_unicode_ci`, so the DB index already folds case and accents; a case-sensitive validation would disagree with the index and let a duplicate through to a `RecordNotUnique`).

- [ ] **Step 5: Run the tests and the rollback**

```bash
flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/nominal_code_test.rb'
bin/rails db:migrate && bin/rails db:rollback:primary STEP=1 && bin/rails db:migrate
```
Expected: PASS, and the rollback reverses cleanly.

- [ ] **Step 6: Commit**

```bash
git commit --no-verify -am "feat(reimbursements): a cost centre owns its list of nominal codes

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Seed the list from the codes budgets already carry

**Files:**
- Create: `app/services/reimbursements/nominal_code_seed.rb`
- Test: `test/services/reimbursements/nominal_code_seed_test.rb`
- Create: `lib/tasks/reimbursements_nominal_codes.rake` (dry by default, `APPLY=1` writes)

**Interfaces:**
- Produces: `NominalCodeSeed.plan` → `[{ cost_centre:, code:, label:, budget_count: }]`; `NominalCodeSeed.apply!`.

**Why a service and a rake task, not a data migration:** test and CI databases are schema-loaded, so a data migration never runs there and could never be tested. `AreaBackfill` and `AreaRename` are both this shape, and both were right.

**The label is a GUESS, so the plan states what it guessed from.** A code's label is derived from the budgets carrying it — their common name, or the most frequent one — and finance edits it afterwards. Never invent a label a human has not seen: the list is what a producer will pick from.

**A budget with a blank code contributes nothing.** `nominal_code` defaults to `""`, so most of the ledger's history may carry blanks; a `""` row in the list is a code nobody can book against.

- [ ] **Step 1: Write the failing test**

```ruby
test "a code is seeded once per cost centre with the count that justified it" do
  fringe = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: fringe)
  create_reimbursements_budget(name: "Other", nominal_code: "432320", cost_centre: fringe)
  create_reimbursements_budget(name: "Set", nominal_code: "", cost_centre: fringe)

  plan = Reimbursements::NominalCodeSeed.plan

  entry = plan.sole
  assert_equal "432320", entry[:code]
  assert_equal 2, entry[:budget_count]
  assert_equal fringe.id, entry[:cost_centre].id
end

test "apply! is idempotent and never duplicates an existing code" do
  fringe = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: fringe)

  Reimbursements::NominalCodeSeed.apply!
  Reimbursements::NominalCodeSeed.apply!

  assert_equal 1, Reimbursements::NominalCode.where(code: "432320", cost_centre: fringe).count
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/nominal_code_seed_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::NominalCodeSeed`.

- [ ] **Step 3: Implement, and decide the unplaced-budget rule explicitly**

A budget with **no** cost centre is lenient-scoped into every centre's screens (`#in_cost_centre`). Seeding its code into *every* centre would invent accounts; seeding it into none loses it. **Rule: seed it into the DEFAULT centre and say so in the plan output**, matching `#expenses_owned_by_cost_centre`'s "an unplaced row falls to the default centre" — and state the count so finance can see what it inherited.

- [ ] **Step 4: The rake task**

```ruby
namespace :reimbursements do
  desc "Seed each cost centre's nominal code list from the codes its budgets carry (APPLY=1 writes)"
  task nominal_code_seed: :environment do
    # print the plan; write only when APPLY=1, as events:backfill_ticket_prices does
  end
end
```

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/'`
Expected: PASS, the whole directory.

- [ ] **Step 6: Commit**

---

### Task 3: Maintain the list on the cost centre's settings page

**Files:**
- Create: `app/controllers/admin/reimbursements/nominal_codes_controller.rb`, `app/views/admin/reimbursements/settings/_nominal_codes.html.erb`
- Modify: `app/controllers/admin/reimbursements/settings_controller.rb`, the cost centre edit view it renders, `config/routes.rb`
- Test: `test/functional/admin/reimbursements/nominal_codes_controller_test.rb`, `test/system/admin/reimbursements/nominal_codes_js_test.rb`

**Interfaces:**
- Consumes: `NominalCode.for_cost_centre`.
- Produces: `/admin/reimbursements/settings/cost_centres/:key/nominal_codes` (index/create/update/destroy).

**Read `settings_controller.rb` first** — it already finds a centre by `key` (`find_by!(key: params[:key])`) and owns the cost-centre create/edit flow. Follow it rather than inventing a second lookup.

**Retiring beats deleting.** A code a budget already carries must not vanish: set `active: false` so it leaves the picker and stays readable on every historical row. Deleting is allowed only for a code no budget references, and the controller checks that rather than trusting the button.

**The form wraps the `CardComponent`, not the other way round.** A `form_with` opened inside the card renders its submit outside the `<form>` and the button silently does nothing — only a browser test clicking the real control catches it, which is why this task has a system test.

- [ ] **Step 1: Write the failing functional test**

```ruby
test "a code in use is retired, not deleted" do
  centre = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  code = create_reimbursements_nominal_code(code: "432320", cost_centre: centre)
  create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: centre)

  delete :destroy, params: { key: centre.key, id: code.id }

  assert code.reload.persisted?, "a code a budget carries must stay readable"
  assert_not code.active?
end

test "a code nothing references is deleted outright" do
  centre = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  code = create_reimbursements_nominal_code(code: "999999", cost_centre: centre)

  delete :destroy, params: { key: centre.key, id: code.id }

  assert_not Reimbursements::NominalCode.exists?(code.id)
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/nominal_codes_controller_test.rb'`
Expected: FAIL — no route.

- [ ] **Step 3: Implement**

Gate on the same permission the rest of Settings uses. **Check what that is before writing it** — `access`/`reimbursements` gates every portal screen, and finance-only actions are gated separately; read `base_controller.rb` and one existing Settings action rather than guessing.

- [ ] **Step 4: The browser test**

Click the real Add button, assert the row appears; click Retire on a code a budget carries, assert it renders as retired rather than vanishing. `select_controller.js` replaces every `.simple-select2` with Tom Select and hides the original `<select>`, so Capybara's `select` raises `ElementNotFound` — click `.ts-control` then the option, as `producer_js_test.rb`'s `tom_select` helper does.

- [ ] **Step 5: Run both suites**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/'` then `bin/rails test:system`
Expected: PASS. **Stop `bin/dev` before the system run** — a live dev server fails ~57 unrelated system tests.

- [ ] **Step 6: Commit**

---

### Task 4: Find-or-create a budget line for `(area, code)`

**Files:**
- Create: `app/services/reimbursements/budget_finder.rb`
- Modify: `app/services/reimbursements/database_store.rb`
- Test: `test/services/reimbursements/budget_finder_test.rb`

**Interfaces:**
- Produces: `BudgetFinder.find_or_create!(area:, nominal_code:, financial_year:, cost_centre:)` → a `Budget`.

**This is Option D's stated end state** — "an `Area` above budgets, `(area, code)` budget found-or-created" — and it is why the area exists at all: a show's Marketing and Other lines share one nominal code, so the code alone cannot identify a line.

**A created line starts with NO agreed figure.** `initial_budget` is written only on create *by the importer*, and it means "the figure the committee agreed", which nobody agreed here. Leave it nil so `Budget#variance` keeps its meaning and the line shows as unbudgeted rather than as a £0 budget — `remaining` nil, never zero, is the same rule.

**It must not create a second line where one exists under another spelling.** Phase 2a's matcher resolves a stored budget under both its bare and its area-prefixed name; this finder matches on `(area_id, nominal_code)`, which is narrower and cannot see a hand-named sibling. **Look up by `(area, code)` first and by the area's existing lines second**, and when two candidates match, RAISE rather than pick — the whole of Phase 2a's matching work says ambiguity blocks and names the rows.

- [ ] **Step 1: Write the failing test**

```ruby
test "an existing line under the same area and code is found, not duplicated" do
  year = create_reimbursements_financial_year
  centre = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  area = create_reimbursements_area(name: "Cogito", financial_year: year, cost_centre: centre)
  existing = create_reimbursements_budget(name: "Marketing", area: area, nominal_code: "432320",
                                          financial_year: year, cost_centre: centre)

  found = Reimbursements::BudgetFinder.find_or_create!(
    area: area, nominal_code: "432320", financial_year: year, cost_centre: centre
  )

  assert_equal existing.id, found.id
  assert_equal 1, area.budgets.where(nominal_code: "432320").count
end

test "a created line carries no agreed figure" do
  year = create_reimbursements_financial_year
  centre = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  area = create_reimbursements_area(name: "Cogito", financial_year: year, cost_centre: centre)

  created = Reimbursements::BudgetFinder.find_or_create!(
    area: area, nominal_code: "432320", financial_year: year, cost_centre: centre
  )

  assert_nil created.initial_budget, "nobody agreed this figure"
  assert_nil created.remaining
  assert_equal area.id, created.area_id
end

test "two candidate lines raise rather than resolving to one" do
  year = create_reimbursements_financial_year
  centre = create_reimbursements_cost_centre(name: "Fringe", key: "fringe")
  area = create_reimbursements_area(name: "Cogito", financial_year: year, cost_centre: centre)
  create_reimbursements_budget(name: "Marketing", area: area, nominal_code: "432320",
                               financial_year: year, cost_centre: centre)
  create_reimbursements_budget(name: "Print", area: area, nominal_code: "432320",
                               financial_year: year, cost_centre: centre)

  assert_raises(Reimbursements::BudgetFinder::AmbiguousError) do
    Reimbursements::BudgetFinder.find_or_create!(
      area: area, nominal_code: "432320", financial_year: year, cost_centre: centre
    )
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/budget_finder_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::BudgetFinder`.

- [ ] **Step 3: Implement**

Creation goes through the store inside one transaction and **re-takes the lookup under a row lock**, the way `create_expense_for_actual!` does — a double-submitted form is exactly how two identical lines get created, and the controller's own check is a read that goes stale.

The created line's name comes from the code's label (Task 1's `NominalCode#label`), not from the area — the area is already beside it everywhere, and `display_name` composes the two.

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/'`
Expected: PASS, the whole directory.

- [ ] **Step 5: Commit**

---

### Task 5: The five debts Phase 2a left behind

**This task is the reason to read Phase 2a's `final-review.md` first.** Each item below was found, ruled on, and deliberately deferred — none is a new idea.

**Files:**
- Modify: `app/controllers/admin/reimbursements/budgets_controller.rb` (M8)
- Modify: `db/migrate/` (a migration restoring area membership on rollback — see below)
- Test: the matching functional, model and integration tests

- [ ] **Step 1: M8 — creating a budget inside an area silently discards the owners you pick**

`budgets_controller.rb:217` reads `budget.area_id` on a `Budget.new`, which is nil before the area is assigned, so the `unless budget.area_id` guard lets `owner_ids` through on create and the area's ownership silently wins. **Phase 2a made this the normal path** — every budget created under an area goes through it.

Write the failing test first: create a budget inside an area while picking two owners, and assert either that the owners are saved *or* that the form refused and said why. **Decide which, and say so in the ledger**: the area owns and its budgets inherit, so the honest behaviour is to not offer the field at all when an area is selected — but the form cannot know that until the area `<select>` changes, which is a Stimulus concern. A browser test clicking the real control is required either way.

- [ ] **Step 2: Phase 1's rollback gap — area MEMBERSHIP is not restored**

A budget survives `BackfillReimbursementsAreas#down` with its name intact but its `area_id` gone, and re-migrating does not restore it: the guard refuses on non-reproducible *areas*, never on non-reproducible *membership*. Reproduce it first (the reviewers did, twice), then decide whether `down` should refuse more broadly or record membership as `AreaRename` records names. **Recording is the shape that worked** — a guard that infers cannot tell a hand-move from a backfilled one.

- [ ] **Step 3: The parked minors, each with its recorded reason**

Read them from `progress.md` rather than this list: `AreaRollup#by_type`'s child inheriting its parent's `lines_out_of_scope`; `#duplicate_rows` being O(n) in distinct lines but not in rows; the em dash reaching SharePoint receipt filenames (**deliberate — the show's name in the filename is the point**; do not "fix" it); and `budget_updates#index`'s area load. Fix what is cheap, and record what you decline.

- [ ] **Step 4: Run both suites, then `hk`**

- [ ] **Step 5: Commit**

---

### Task 6: Close the rename's rollback window — LAST, and only on Mick's word

**Files:**
- Create: `db/migrate/<stamp>_drop_name_before_area_rename.rb`

**Do not run this task until the Phase 2a rename has been live long enough that rolling it back is off the table.** Dropping `reimbursements_budgets.name_before_area_rename` makes the rename **permanently irreversible** — `AreaRename.restore!` reads that column and raises `MissingRecordError` when it is gone, deliberately, so the failure is loud rather than a silent no-op.

**The migration must say this in its own body**, because the next person reads *this* migration, not Phase 2a's:

```ruby
# Dropping this column closes the Phase 2a rename's rollback window FOR GOOD:
# AreaRename.restore! reads it to put back the exact strings #strip! took off,
# and raises MissingRecordError once it is gone. Only run this when rolling the
# rename back is no longer a decision anyone would make.
```

- [ ] **Step 1: Confirm with Mick, in so many words, that the window may close**
- [ ] **Step 2: Write the migration with the comment above, explicit `up`/`down`**
- [ ] **Step 3: Prove `down` re-adds the column and `restore!` raises while it is absent**
- [ ] **Step 4: Commit**

---

## Open questions for Mick

1. **Is an area's agreed total an EXPENSE budget?** Phase 2a suppressed the "not yet allocated" figure for an area holding both expense and income lines rather than answer this, because the honest label depends on what "an overall budget for a show" means. If it caps spending only, the Expense-only reading is right and the figure can come back.
2. **Are a loose `Marketing` and Cogito's `Marketing` legitimately two lines?** Phase 2a blocks a sheet carrying both, which is safe but refuses a sheet the committee might reasonably write. Option D's end state suggests yes, they are distinct.
3. **Is the mechanical closure worth building?** A test walking every reimbursements screen with two identically-named budgets seeded, failing on any bare name outside a rowgroup heading. Four sweeps each found sites the previous one missed; grepping cannot close that class. Expensive, and nobody has built it.
