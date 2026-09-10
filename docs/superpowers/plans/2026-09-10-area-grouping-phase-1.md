# Area Grouping — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a show's budget lines a parent, so its spend can be seen together, given one agreed total and one owner.

**Architecture:** A new `Reimbursements::Area` sits above `Reimbursements::Budget` via a nullable `area_id`. The area holds the authoritative figure and the owners; a budget's own figure becomes optional and its owners are inherited from its area when it has one. Nothing on the EUSA-facing side moves — the nominal code stays on the budget, so the BACS spreadsheet, the exports and Reconcile's income match are untouched.

**Tech Stack:** Rails 8.1, MySQL (multi-database: `primary`, `queue`, `cache`), minitest with fixtures, ViewComponents, simple_form + `FormStyles`, Tailwind v4.

**Spec:** [docs/superpowers/specs/2026-09-10-area-grouping-design.md](../specs/2026-09-10-area-grouping-design.md)

**Phase 2 (separate plan, after this lands):** `Reimbursements::NominalCode` + maintenance on the cost centre edit page, find-or-create of a budget from a claim, the importer's `Area` column and re-home bucket, the overview's area rollup, and the `Area` column in the exports.

## Global Constraints

- **Multi-database app.** `bin/rails db:rollback:primary STEP=n` — a bare `db:rollback` errors. Run the rollback for every migration in this plan and confirm it reverses.
- **Legacy tables use integer primary keys.** `reimbursements_*` tables are all bigint, so `t.references … type: :bigint` is right here — but never assume it for a table outside that namespace.
- **The area is authoritative, a budget's figure is optional.** `reimbursements_budgets.initial_budget` is already nullable and the readers already return nil rather than lying (`projected_amount`, `remaining`, `variance`). Do not add a presence validation to it.
- **Ownership: the area owns, its budgets inherit.** A budget with no area keeps its own owners.
- **Test databases are schema-LOADED, not migrated**, so a data migration never runs there. Anything the tests need must be created by the test, not by a migration.
- **Fixtures: `test/fixtures/reimbursements/cost_centres.yml` stays at ONE row.** A second centre comes from `create_second_reimbursements_cost_centre` (`test/support/reimbursements_test_helpers.rb`).
- **No mocking library.** No mocha, no `minitest/mock`. Stub externals by toggling config.
- **`git stash` is banned** — `refs/stash` is shared by every worktree. Commit with `--no-verify` and run `hk run check --from-ref <base> --to-ref HEAD` at the end.
- Serialize test runs behind `flock /tmp/bl-test.lock -c '<cmd>'`, echoing before the wait.
- **Any form you add gets a system test that clicks the real button.** Two defects on 2026-09-10 passed a green 4200-test suite because request-level tests posted parameters the browser never sends.
- Buttons via `ButtonComponent` / `btn_classes` / `get_link`. Forms via `FormStyles` and `shared/form/field`. A `form_with` opened INSIDE a `CardComponent` renders its submit outside the `<form>` and the button silently does nothing.
- Every commit message ends with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Responsibility |
|---|---|
| `db/migrate/*_create_reimbursements_areas.rb` | `reimbursements_areas` + `reimbursements_budgets.area_id` |
| `db/migrate/*_create_reimbursements_area_owners.rb` | the Area↔Person join |
| `db/migrate/*_allow_area_budget_forecasts.rb` | `budget_forecasts.area_id`, `budget_id` nullable, exactly-one check |
| `db/migrate/*_backfill_reimbursements_areas.rb` | the one-off colon split + owner union |
| `app/models/reimbursements/area.rb` | the record: scoping, figures, owners |
| `app/models/reimbursements/area_owner.rb` | the join |
| `app/models/reimbursements/budget.rb` | `belongs_to :area`, owner resolution |
| `app/models/reimbursements/budget_forecast.rb` | belongs to a budget OR an area |
| `app/services/reimbursements/database_store.rb` | `areas`, `areas_for_year`, `find_area`, writers |
| `app/controllers/admin/reimbursements/areas_controller.rb` | area CRUD + nested budget fields |
| `app/views/admin/reimbursements/areas/*` | index / new / edit / `_fields` |
| `app/views/admin/reimbursements/budgets/*` | area picker on the budget form; grouping on the index |

---

### Task 1: The Area record and `budgets.area_id`

**Files:**
- Create: `db/migrate/20260911100000_create_reimbursements_areas.rb`
- Create: `app/models/reimbursements/area.rb`
- Modify: `app/models/reimbursements/budget.rb` (associations, near `:51`)
- Test: `test/models/reimbursements/area_test.rb`

**Interfaces:**
- Produces: `Reimbursements::Area` with `#record_id` (String, the id — mirrors `Budget#record_id`), `#name`, `#initial_budget`, `#cost_centre`, `#financial_year`, `#budgets`, `#active`. `Budget#area` / `Budget#area_id`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/area_test.rb
require "test_helper"

module Reimbursements
  class AreaTest < ActiveSupport::TestCase
    test "requires a name" do
      area = Area.new(name: "")
      assert_not area.valid?
      assert area.errors[:name].present?
    end

    test "a budget belongs to an area, and an area-less budget is still valid" do
      area = create_reimbursements_area(name: "Cogito")
      in_area = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      loose = create_reimbursements_budget(name: "Contingency")

      assert_equal area, in_area.area
      assert_nil loose.area
      assert_equal [ in_area ], area.budgets.to_a
    end

    test "record_id is the id as a string, like a budget's" do
      area = create_reimbursements_area(name: "Cogito")
      assert_equal area.id.to_s, area.record_id
    end
  end
end
```

Add the helper beside the other `create_reimbursements_*` helpers:

```ruby
# test/support/reimbursements_test_helpers.rb
def create_reimbursements_area(name:, cost_centre: nil, financial_year: nil, **attrs)
  Reimbursements::Area.create!(
    name: name,
    cost_centre: cost_centre,
    financial_year: financial_year || Reimbursements::FinancialYear.current,
    **attrs
  )
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_test.rb'`
Expected: FAIL — `NameError: uninitialized constant Reimbursements::Area`

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20260911100000_create_reimbursements_areas.rb
class CreateReimbursementsAreas < ActiveRecord::Migration[8.1]
  # A show, project or heading that several budget lines belong to. Both cost
  # centres already invented this: Fringe writes it into budget NAMES
  # ("Cogito: Marketing"), termtime writes it as amountless header rows in its
  # spreadsheet. Neither survived the import.
  def change
    create_table :reimbursements_areas do |t|
      t.string  :name, null: false
      t.decimal :initial_budget, precision: 12, scale: 2
      t.text    :notes
      t.boolean :active, null: false, default: true
      t.references :cost_centre, type: :bigint, null: true,
                                 foreign_key: { to_table: :reimbursements_cost_centres }, index: true
      t.references :financial_year, type: :bigint, null: true,
                                    foreign_key: { to_table: :reimbursements_financial_years }, index: true

      t.timestamps

      # Matched by name within one (year, centre) — the same rule BudgetImport
      # uses for a budget line, so an area recurs each year as a budget does.
      t.index %i[financial_year_id cost_centre_id name],
              name: "index_reimbursements_areas_on_year_centre_name"
    end

    add_reference :reimbursements_budgets, :area, type: :bigint, null: true,
                  foreign_key: { to_table: :reimbursements_areas }, index: true
  end
end
```

Note the composite index is declared INSIDE `create_table`. A standalone `add_index` beside a `create_table` makes the migration irreversible.

- [ ] **Step 4: Write the model**

```ruby
# app/models/reimbursements/area.rb
module Reimbursements
  ##
  # A show, project or heading that several budget lines belong to.
  #
  # The area holds the AGREED TOTAL and the owners; its budgets hold the
  # nominal code (EUSA's axis) and an optional allocation. See
  # docs/superpowers/specs/2026-09-10-area-grouping-design.md.
  class Area < ApplicationRecord
    self.table_name = "reimbursements_areas"

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre", optional: true
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :nullify,
                       inverse_of: :area

    validates :name, presence: true

    # String id, matching Budget#record_id — the store's vocabulary is strings.
    def record_id = id.to_s
  end
end
```

And on `Budget`, beside its other associations:

```ruby
belongs_to :area, class_name: "Reimbursements::Area", optional: true, inverse_of: :budgets
```

- [ ] **Step 5: Migrate, run the tests, prove the rollback**

```bash
bin/rails db:migrate
flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_test.rb'
bin/rails db:rollback:primary STEP=1   # must succeed
bin/rails db:migrate
```
Expected: 3 runs, 0 failures; rollback exits 0 and drops both the table and `budgets.area_id`.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/reimbursements/area.rb \
        app/models/reimbursements/budget.rb test/models/reimbursements/area_test.rb \
        test/support/reimbursements_test_helpers.rb
git commit --no-verify -m "feat(reimbursements): a budget line can belong to an area

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Ownership — the area owns, its budgets inherit

**Files:**
- Create: `db/migrate/20260911100100_create_reimbursements_area_owners.rb`
- Create: `app/models/reimbursements/area_owner.rb`
- Modify: `app/models/reimbursements/area.rb`, `app/models/reimbursements/budget.rb:61-82`
- Test: `test/models/reimbursements/area_ownership_test.rb`

**Interfaces:**
- Consumes: `Reimbursements::Area` (Task 1).
- Produces: `Area#owners`, `Area#owner_ids` (Array of Person record-id Strings), `Area#sync_owner_ids!(ids)`. `Budget#owners` and `Budget#owner_ids` keep their existing signatures but resolve through the area when one is set — this is what leaves `Reimbursements::OwnerReview` untouched.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/area_ownership_test.rb
require "test_helper"

module Reimbursements
  class AreaOwnershipTest < ActiveSupport::TestCase
    setup do
      @alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      @bob   = create_reimbursements_person(name: "Bob", email: "bob@example.com")
    end

    test "a budget in an area inherits the area's owners" do
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      assert_equal [ @alice.record_id ], budget.owner_ids
    end

    test "a budget with no area keeps its own owners" do
      budget = create_reimbursements_budget(name: "Contingency")
      budget.sync_owner_ids!([ @bob.id ])

      assert_equal [ @bob.record_id ], budget.owner_ids
    end

    test "the area's owners WIN over rows left on the budget" do
      # The backfill keeps budget_owners rows so it can be reversed; they must
      # not also apply, or a claim would need two people's sign-off.
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      budget.sync_owner_ids!([ @bob.id ])

      assert_equal [ @alice.record_id ], budget.owner_ids
    end

    test "the owner gate reads the inherited owner" do
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      assert OwnerReview.gate_applies?(budget)
      assert OwnerReview.owned_by?(budget, @alice)
    end
  end
end
```

(If `OwnerReview`'s methods take different arguments, call them exactly as
`app/services/reimbursements/owner_review.rb` defines them — read it first. The
point of the test is that the gate sees the inherited owner without being changed.)

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_ownership_test.rb'`
Expected: FAIL — `NoMethodError: undefined method 'sync_owner_ids!' for an instance of Reimbursements::Area`

- [ ] **Step 3: Write the migration and the join model**

```ruby
# db/migrate/20260911100100_create_reimbursements_area_owners.rb
class CreateReimbursementsAreaOwners < ActiveRecord::Migration[8.1]
  # Mirrors reimbursements_budget_owners exactly. Owners are People (payees),
  # not user accounts.
  def change
    create_table :reimbursements_area_owners do |t|
      t.references :area, type: :bigint, null: false,
                          foreign_key: { to_table: :reimbursements_areas }, index: true
      t.references :person, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_people }, index: true

      t.timestamps

      t.index %i[area_id person_id], unique: true,
              name: "index_reimbursements_area_owners_on_area_id_and_person_id"
    end
  end
end
```

```ruby
# app/models/reimbursements/area_owner.rb
module Reimbursements
  class AreaOwner < ApplicationRecord
    self.table_name = "reimbursements_area_owners"

    belongs_to :area, class_name: "Reimbursements::Area", inverse_of: :area_ownerships
    belongs_to :person, class_name: "Reimbursements::Person"
  end
end
```

- [ ] **Step 4: Write the resolution**

On `Area`:

```ruby
has_many :area_ownerships, class_name: "Reimbursements::AreaOwner", dependent: :destroy,
                           inverse_of: :area
has_many :owners, through: :area_ownerships, source: :person

def owner_ids = owners.map(&:record_id)

def sync_owner_ids!(person_ids)
  person_ids = person_ids.map(&:to_i)
  area_ownerships.where.not(person_id: person_ids).destroy_all
  (person_ids - area_ownerships.pluck(:person_id)).each do |person_id|
    area_ownerships.create!(person_id: person_id)
  end
end
```

On `Budget`, rename the existing association and resolve through the area:

```ruby
# The rows on the budget itself. Read directly ONLY when the budget has no
# area — the backfill leaves them in place so it can be reversed, so a budget
# in an area has both, and the area's are the live ones.
has_many :budget_ownerships, class_name: "Reimbursements::BudgetOwner", dependent: :destroy
has_many :own_owners, through: :budget_ownerships, source: :person

# The area owns and its budgets inherit; a budget with no area owns itself.
def owners = area ? area.owners : own_owners

def owner_ids = owners.map(&:record_id)
```

Grep for every existing reader of `Budget#owners` / `#owner_ids` before changing
the association name, and update any that meant the budget's own rows.

- [ ] **Step 5: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_ownership_test.rb test/services/reimbursements/owner_review_test.rb'`
Expected: PASS, including the pre-existing owner-review tests unchanged.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/reimbursements/ test/models/reimbursements/area_ownership_test.rb
git commit --no-verify -m "feat(reimbursements): an area owns, and its budgets inherit

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: A forecast attaches to an area or a budget, exactly one

**Files:**
- Create: `db/migrate/20260911100200_allow_area_budget_forecasts.rb`
- Modify: `app/models/reimbursements/budget_forecast.rb`, `app/models/reimbursements/area.rb`
- Test: `test/models/reimbursements/budget_forecast_test.rb`

**Interfaces:**
- Produces: `BudgetForecast#area`, and on `Area`: `#forecasts`, `#current_forecast` (BigDecimal or nil), `#projected_amount` (`current_forecast || initial_budget`).

**Why not area-only forecasts:** 14 of Fringe's 31 budgets have no area — payroll, NI, Consumables, PRS/PPL, Contingency — and Contingency is the one line the 2026-09-08 import revised. A pure area-level log could only express that by inventing a single-child area per overhead.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/budget_forecast_test.rb (add to the existing file)
test "a forecast may belong to an area instead of a budget" do
  area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
  BudgetForecast.create!(area: area, amount: 800, date: Date.current)

  assert_equal 800, area.current_forecast
  assert_equal 800, area.projected_amount
end

test "an area with no forecast projects its initial budget" do
  area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
  assert_nil area.current_forecast
  assert_equal 1_000, area.projected_amount
end

test "a forecast belonging to both, or to neither, is refused" do
  area = create_reimbursements_area(name: "Cogito")
  budget = create_reimbursements_budget(name: "Contingency")

  assert_not BudgetForecast.new(area: area, budget: budget, amount: 1).valid?
  assert_not BudgetForecast.new(amount: 1).valid?
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_forecast_test.rb'`
Expected: FAIL — unknown attribute `area`.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20260911100200_allow_area_budget_forecasts.rb
class AllowAreaBudgetForecasts < ActiveRecord::Migration[8.1]
  # An AREA forecast revises the show's agreed total; a BUDGET forecast revises
  # how much of it a category is allocated. One BudgetUpdate groups both, so a
  # committee meeting stays one update.
  def up
    add_reference :reimbursements_budget_forecasts, :area, type: :bigint, null: true,
                  foreign_key: { to_table: :reimbursements_areas }, index: true
    change_column_null :reimbursements_budget_forecasts, :budget_id, true
  end

  def down
    # Area forecasts have no home once the column goes; refuse rather than
    # silently dropping revisions to an agreed total.
    if Reimbursements::BudgetForecast.where.not(area_id: nil).exists?
      raise ActiveRecord::IrreversibleMigration,
            "area forecasts exist — reassign or delete them before rolling back"
    end

    change_column_null :reimbursements_budget_forecasts, :budget_id, false
    remove_reference :reimbursements_budget_forecasts, :area
  end
end
```

- [ ] **Step 4: Write the model changes**

```ruby
# app/models/reimbursements/budget_forecast.rb
belongs_to :budget, class_name: "Reimbursements::Budget", optional: true
belongs_to :area, class_name: "Reimbursements::Area", optional: true, inverse_of: :forecasts

validate :belongs_to_exactly_one_owner

private

# Enforced in the model rather than as a DB check constraint: MySQL's CHECK
# support varies by version here, and a validation gives the operator a message.
def belongs_to_exactly_one_owner
  return if budget_id.present? ^ area_id.present?

  errors.add(:base, "must belong to either a budget or an area, not both and not neither")
end
```

On `Area` (mirroring `Budget#current_forecast` at `budget.rb:105-136` — read it and match the ordering exactly):

```ruby
has_many :forecasts, class_name: "Reimbursements::BudgetForecast", dependent: :destroy,
                     inverse_of: :area

# Latest wins, by date then id — the same rule Budget#current_forecast uses.
def current_forecast
  @current_forecast ||= forecasts.max_by { |f| [ f.date || Date.new(0), f.id ] }&.amount
end

def projected_amount = current_forecast || initial_budget
```

- [ ] **Step 5: Run the tests and prove the rollback**

```bash
bin/rails db:migrate
flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/budget_forecast_test.rb'
bin/rails db:rollback:primary STEP=1   # succeeds while no area forecasts exist
bin/rails db:migrate
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/reimbursements/ test/models/reimbursements/budget_forecast_test.rb
git commit --no-verify -m "feat(reimbursements): a forecast revises an area's total or a budget's allocation

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The area's figures

**Files:**
- Modify: `app/models/reimbursements/area.rb`
- Test: `test/models/reimbursements/area_figures_test.rb`

**Interfaces:**
- Produces: `Area#committed_amount`, `#remaining`, `#allocated`, `#unallocated`, `#income?`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/area_figures_test.rb
require "test_helper"

module Reimbursements
  class AreaFiguresTest < ActiveSupport::TestCase
    setup do
      @area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      @marketing = create_reimbursements_budget(name: "Cogito: Marketing", area: @area,
                                                initial_budget: 400)
      @other = create_reimbursements_budget(name: "Cogito: Other", area: @area)  # no allocation
    end

    test "allocated skips lines with no agreed figure" do
      assert_equal 400, @area.allocated
      assert_equal 600, @area.unallocated
    end

    test "committed sums its budgets' committed spend" do
      person = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      create_reimbursements_expense(person: person, budget: @marketing,
                                    amount: 150, amount_excl_vat: 150,
                                    status: Status::APPROVED)

      assert_equal 150, @area.committed_amount
      assert_equal 850, @area.remaining
    end

    test "an area with no agreed total has no remaining, rather than a wrong one" do
      area = create_reimbursements_area(name: "Improverts")
      assert_nil area.remaining
    end
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_figures_test.rb'`
Expected: FAIL — `undefined method 'allocated'`

- [ ] **Step 3: Implement**

```ruby
# app/models/reimbursements/area.rb
# The spend its budgets have committed — Approved, Submitted and Paid, ex-VAT,
# exactly as Budget#committed_amount counts it.
def committed_amount
  @committed_amount ||= budgets.sum(&:committed_amount)
end

# What is left of the AGREED total. Nil when nobody agreed one, rather than
# reading as the whole spend being over budget.
def remaining
  return nil if projected_amount.nil?

  projected_amount - committed_amount
end

# How much of the total has been split out into category lines. Lines with no
# agreed figure are skipped, not counted as zero.
def allocated
  @allocated ||= budgets.filter_map(&:projected_amount).sum
end

# The part of the agreed total not yet assigned to a category — NOT spare money.
def unallocated
  return nil if projected_amount.nil?

  projected_amount - allocated
end

def income? = budgets.any?(&:income?)
```

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_figures_test.rb'`
Expected: PASS (3 runs).

- [ ] **Step 5: Commit**

```bash
git add app/models/reimbursements/area.rb test/models/reimbursements/area_figures_test.rb
git commit --no-verify -m "feat(reimbursements): an area totals its lines without inventing figures

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The backfill

**Files:**
- Create: `db/migrate/20260911100300_backfill_reimbursements_areas.rb`
- Test: `test/models/reimbursements/area_backfill_test.rb`

**Interfaces:**
- Produces: `Reimbursements::AreaBackfill.run!(cost_centre: nil)` in `app/services/reimbursements/area_backfill.rb` — the migration calls it, and the test calls it directly, because **test databases are schema-loaded so the migration never runs there**.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/reimbursements/area_backfill_test.rb
require "test_helper"

module Reimbursements
  class AreaBackfillTest < ActiveSupport::TestCase
    test "splits Area: Category names, tolerating extra whitespace" do
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      c = create_reimbursements_budget(name: "Improverts:  Retreat")  # two spaces

      AreaBackfill.run!

      assert_equal "Cogito", a.reload.area.name
      assert_equal a.area, b.reload.area
      assert_equal "Improverts", c.reload.area.name
    end

    test "leaves a budget with no colon alone" do
      budget = create_reimbursements_budget(name: "Contingency")
      AreaBackfill.run!
      assert_nil budget.reload.area
    end

    test "seeds the area's owners from the union of its budgets'" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      a.sync_owner_ids!([ alice.id ])
      b.sync_owner_ids!([ bob.id ])

      AreaBackfill.run!

      assert_equal [ alice.record_id, bob.record_id ].sort, a.reload.area.owner_ids.sort
    end

    test "keeps the budgets' own owner rows, so the backfill can be reversed" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      budget.sync_owner_ids!([ alice.id ])

      AreaBackfill.run!

      assert_equal [ alice.record_id ], budget.reload.own_owners.map(&:record_id)
    end

    test "does not re-home a budget that already has an area" do
      area = create_reimbursements_area(name: "Somewhere else")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      AreaBackfill.run!

      assert_equal area, budget.reload.area
    end
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_backfill_test.rb'`
Expected: FAIL — `uninitialized constant Reimbursements::AreaBackfill`

- [ ] **Step 3: Implement the service**

```ruby
# app/services/reimbursements/area_backfill.rb
module Reimbursements
  ##
  # One-off: give the budgets whose names already read "Area: Category" a real
  # area. Fringe wrote the grouping into 17 of its 31 budget names; the other 14
  # are genuine standalone overheads and are left alone.
  #
  # A SERVICE rather than migration code, because test and CI databases are
  # schema-loaded, so a data migration never runs there and could never be
  # tested.
  module AreaBackfill
    NAME_PATTERN = /\A(?<area>[^:]+):\s*(?<category>.+)\z/

    def self.run!(scope: Budget.all)
      scope.where(area_id: nil).find_each do |budget|
        match = NAME_PATTERN.match(budget.name.to_s)
        next if match.nil?

        area = find_or_create_area(budget, match[:area].strip)
        budget.update_column(:area_id, area.id)
      end

      seed_owners!
    end

    def self.find_or_create_area(budget, name)
      Area.find_or_create_by!(name: name,
                              cost_centre_id: budget.cost_centre_id,
                              financial_year_id: budget.financial_year_id)
    end
    private_class_method :find_or_create_area

    # An area with no owners means its budgets' claims silently stop hitting the
    # owner gate — the worst way to get this wrong. Seed from the union of the
    # children's, and KEEP their rows so the backfill has a true reverse.
    def self.seed_owners!
      Area.includes(budgets: :own_owners).find_each do |area|
        next if area.owner_ids.any?

        person_ids = area.budgets.flat_map { |b| b.own_owners.map(&:id) }.uniq
        area.sync_owner_ids!(person_ids) if person_ids.any?
      end
    end
    private_class_method :seed_owners!
  end
end
```

```ruby
# db/migrate/20260911100300_backfill_reimbursements_areas.rb
class BackfillReimbursementsAreas < ActiveRecord::Migration[8.1]
  def up
    Reimbursements::AreaBackfill.run!
  end

  def down
    # Detach, then drop the areas this created. The budgets' own owner rows were
    # deliberately kept, so ownership returns to exactly where it was.
    Reimbursements::Budget.where.not(area_id: nil).update_all(area_id: nil)
    Reimbursements::AreaOwner.delete_all
    Reimbursements::Area.delete_all
  end
end
```

- [ ] **Step 4: Run the tests, then the migration, then its rollback**

```bash
flock /tmp/bl-test.lock -c 'bin/rails test test/models/reimbursements/area_backfill_test.rb'
bin/rails db:migrate
bin/rails db:rollback:primary STEP=1
bin/rails db:migrate
```
Expected: 5 runs, 0 failures; rollback exits 0.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb app/services/reimbursements/area_backfill.rb \
        test/models/reimbursements/area_backfill_test.rb
git commit --no-verify -m "feat(reimbursements): backfill areas from the Area: Category names

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Store readers

**Files:**
- Modify: `app/services/reimbursements/database_store.rb`
- Test: `test/services/reimbursements/database_store_test.rb`

**Interfaces:**
- Produces: `store.areas` (unscoped, memoized — an id→record lookup, like `#budgets`), `store.areas_for_year` (year- AND cost-centre scoped, like `#budgets_for_year`), `store.find_area(record_id)`, `store.create_area!(attrs)`, `store.update_area!(record_id, attrs)`, `store.sync_area_owners!(record_id, person_ids)`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/reimbursements/database_store_test.rb (add)
test "areas is unscoped and areas_for_year is scoped to year and cost centre" do
  other = create_second_reimbursements_cost_centre
  mine = create_reimbursements_area(name: "Cogito", cost_centre: Reimbursements::CostCentre.default)
  theirs = create_reimbursements_area(name: "Panto", cost_centre: other)

  store = Reimbursements::DatabaseStore.new(
    financial_year: Reimbursements::FinancialYear.current,
    cost_centre: Reimbursements::CostCentre.default
  )

  assert_includes store.areas, theirs, "areas is an id->record lookup and must not be narrowed"
  assert_includes store.areas_for_year, mine
  assert_not_includes store.areas_for_year, theirs
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/database_store_test.rb -n /areas/'`
Expected: FAIL — `undefined method 'areas'`

- [ ] **Step 3: Implement, beside the budget readers**

```ruby
# Every area, every year — an id->record lookup, for exactly the reason
# #budgets is unscoped: narrowing it blanks the area name on another year's or
# another centre's claim.
def areas
  @areas ||= Area.includes(:owners, :budgets).to_a
end

# The areas the budget screens LIST.
def areas_for_year
  @areas_for_year ||= scoped_to_cost_centre(scoped_to_year(areas), &:cost_centre_id)
end

def find_area(record_id)
  Area.includes(:owners, :budgets, :forecasts).find_by(id: record_id)
end

def create_area!(attrs)
  Area.create!(area_columns(attrs))
end

def update_area!(record_id, attrs)
  area = Area.find(record_id)
  area.update!(area_columns(attrs))
  bust_areas!
  area
end

def sync_area_owners!(record_id, person_ids)
  Area.find(record_id).sync_owner_ids!(person_ids)
  bust_areas!
end
```

Add `@areas = nil; @areas_for_year = nil` to a new private `bust_areas!` beside `bust_budgets!`, and a private `area_columns(attrs)` that slices the permitted keys (`name`, `initial_budget`, `notes`, `active`, `cost_centre`, `financial_year`) the way `expense_columns` does.

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/services/reimbursements/database_store_test.rb'`
Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git add app/services/reimbursements/database_store.rb test/services/reimbursements/database_store_test.rb
git commit --no-verify -m "feat(reimbursements): read and write areas through the store

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The areas admin screen, with its budgets as nested fields

**Files:**
- Create: `app/controllers/admin/reimbursements/areas_controller.rb`
- Create: `app/views/admin/reimbursements/areas/{index,new,edit,_fields}.html.erb`
- Modify: `config/routes.rb` (beside `resources :budgets`), `app/helpers/navigation_helper.rb`
- Modify: `app/models/reimbursements/area.rb` (`accepts_nested_attributes_for :budgets`)
- Test: `test/functional/admin/reimbursements/areas_controller_test.rb`, `test/system/admin/reimbursements/areas_js_test.rb`

**Interfaces:**
- Consumes: `store.areas_for_year`, `store.create_area!`, `store.update_area!`, `store.sync_area_owners!` (Task 6).

- [ ] **Step 1: Write the failing functional test**

```ruby
# test/functional/admin/reimbursements/areas_controller_test.rb
require "test_helper"

module Admin
  module Reimbursements
    class AreasControllerTest < ActionController::TestCase
      tests Admin::Reimbursements::AreasController

      setup do
        @user = users(:admin)
        grant_finance_permission(@user)
        sign_in @user
      end

      test "index requires the finance permission" do
        sign_in users(:committee)
        get :index
        assert_redirected_to root_path
      end

      test "creates an area with its owners" do
        person = create_reimbursements_person(name: "Alice", email: "alice@example.com")

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :create, params: { name: "Cogito", initial_budget: "£1,200",
                                  owner_ids: [ person.record_id ] }
        end

        area = ::Reimbursements::Area.order(:id).last
        assert_equal "Cogito", area.name
        assert_equal 1200, area.initial_budget, "a typed £1,200 must not store as 0"
        assert_equal [ person.record_id ], area.owner_ids
      end

      test "adds a budget line to an area through nested attributes" do
        area = create_reimbursements_area(name: "Cogito")

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320" } }
          }
        end

        assert_equal "Cogito: Marketing", area.reload.budgets.last.name
      end

      test "detaching a budget nils its area rather than deleting it" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { id: budget.id, area_id: "" } }
          }
        end

        assert_nil budget.reload.area
      end
    end
  end
end
```

**The `£1,200` assertion is not decoration.** AR casts a String to a decimal column with `to_d`, so a raw `"£1,200"` stores **0**. The controller must write the BigDecimal from `Reimbursements::AmountParser` / `AmountValidation.amount`, never the param.

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/areas_controller_test.rb'`
Expected: FAIL — uninitialized constant `Admin::Reimbursements::AreasController`

- [ ] **Step 3: Route, controller, views**

Route, beside `resources :budgets` in `config/routes.rb`:

```ruby
resources :areas, only: %i[index new create edit update]
```

Controller — subclass `FinanceController` so it inherits the finance permission, the `?year=` and `?cost_centre=` selectors and the scoped store:

```ruby
# app/controllers/admin/reimbursements/areas_controller.rb
module Admin
  module Reimbursements
    class AreasController < FinanceController
      before_action :set_area, only: %i[edit update]

      def index
        @title = "Areas"
        @areas = paginate(store.areas_for_year)
      end

      def new
        @title = "New area"
        @area = ::Reimbursements::Area.new
        @people = store.people
      end

      def create
        attrs = area_params
        if (error = validation_error(attrs))
          @title = "New area"
          @area = ::Reimbursements::Area.new(name: params[:name])
          @people = store.people
          flash.now[:alert] = error
          return render(:new, status: :unprocessable_entity)
        end

        area = store.create_area!(attrs.merge(financial_year: selected_financial_year,
                                              cost_centre: chosen_cost_centre))
        store.sync_area_owners!(area.record_id, Array(params[:owner_ids]).compact_blank)
        redirect_to edit_admin_reimbursements_area_path(area.record_id), notice: "Area created."
      end

      def edit
        @title = "Area: #{@area.name}"
        @people = store.people
      end

      def update
        attrs = area_params
        if (error = validation_error(attrs))
          @title = "Area: #{@area.name}"
          @people = store.people
          flash.now[:alert] = error
          return render(:edit, status: :unprocessable_entity)
        end

        @area.assign_attributes(attrs)
        @area.budgets_attributes = params[:budgets_attributes].to_unsafe_h if params[:budgets_attributes]
        @area.save!
        store.sync_area_owners!(@area.record_id, Array(params[:owner_ids]).compact_blank)
        redirect_to edit_admin_reimbursements_area_path(@area.record_id), notice: "Area saved."
      end

      private

      def set_area
        @area = store.find_area(params[:id]) or return head(:not_found)
      end

      # The PARSED BigDecimal, never the raw param: AR casts a String to a
      # decimal column with to_d, so a typed "£1,200" would store as 0.
      def area_params
        { name: params[:name].to_s.strip,
          initial_budget: ::Reimbursements::AmountParser.parse(params[:initial_budget]),
          notes: params[:notes].to_s,
          active: ActiveModel::Type::Boolean.new.cast(params[:active]) }
      end

      def validation_error(attrs)
        return "Enter a name." if attrs[:name].blank?
        return "That budget figure isn't a number I can read." if
          params[:initial_budget].present? && attrs[:initial_budget].nil?

        nil
      end
    end
  end
end
```

`Area` gains:

```ruby
accepts_nested_attributes_for :budgets, allow_destroy: false, reject_if: :all_blank
```

`allow_destroy: false` is deliberate — detaching sets `area_id` to nil, and a
budget is never deleted from here, because its claims and history hang off it.

The `_fields` partial renders the area's own fields and then its budgets through
`shared/form/sections/_nested_fields`. These are a real association, so unlike
`ticket_prices` no `template_object:` is needed.

- [ ] **Step 4: Write the system test that clicks the real button**

```ruby
# test/system/admin/reimbursements/areas_js_test.rb
test "adds a budget line to an area in the browser" do
  area = create_reimbursements_area(name: "Cogito")
  sign_in_as_finance

  visit edit_admin_reimbursements_area_path(area.record_id)
  click_on "Add budget line"
  within all("[data-nested-form-target='item']").last do
    fill_in "Name", with: "Cogito: Marketing"
    fill_in "Nominal code", with: "432320"
  end
  click_on "Save"

  assert_text "Area saved"
  assert_equal "Cogito: Marketing", area.reload.budgets.last&.name
end
```

- [ ] **Step 5: Run both, then the whole suite**

```bash
flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/areas_controller_test.rb'
flock /tmp/bl-test.lock -c 'bin/rails test:system TEST=test/system/admin/reimbursements/areas_js_test.rb'
```
Expected: PASS both. If the system test fails with the submit doing nothing, check the `form_with` is OUTSIDE the `CardComponent`.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/reimbursements/areas_controller.rb \
        app/views/admin/reimbursements/areas app/models/reimbursements/area.rb \
        app/helpers/navigation_helper.rb test/functional/admin/reimbursements/areas_controller_test.rb \
        test/system/admin/reimbursements/areas_js_test.rb
git commit --no-verify -m "feat(reimbursements): manage an area and its budget lines

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: An area picker on the budget form

**Files:**
- Modify: `app/views/admin/reimbursements/budgets/_fields.html.erb`, `app/controllers/admin/reimbursements/budgets_controller.rb` (`new`/`create`/`edit`/`update`, around `:45-90`)
- Test: `test/functional/admin/reimbursements/budgets_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
test "a budget can be moved between areas from its own form" do
  from = create_reimbursements_area(name: "Cogito")
  to = create_reimbursements_area(name: "Improverts")
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: from)

  patch :update, params: { id: budget.record_id, name: budget.name,
                           nominal_code: budget.nominal_code, area_id: to.record_id }

  assert_equal to, budget.reload.area
end

test "clearing the area detaches the budget" do
  area = create_reimbursements_area(name: "Cogito")
  budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

  patch :update, params: { id: budget.record_id, name: budget.name,
                           nominal_code: budget.nominal_code, area_id: "" }

  assert_nil budget.reload.area
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/budgets_controller_test.rb -n /area/'`
Expected: FAIL — the area is unchanged.

- [ ] **Step 3: Implement**

Pass `@areas = store.areas_for_year` from `new`/`create`/`edit`/`update`, and in
`_fields`:

```erb
<%= render "shared/form/field", label: "Area", name: :area_id,
      hint: "Leave blank for a standalone line like Contingency or payroll." do %>
  <%# ONLY simple-select2: Tom Select copies the select's classes onto its own
      wrapper, which already draws the box, so a border/width here renders a
      box inside a box. %>
  <%= select_tag :area_id,
        options_from_collection_for_select(areas, :record_id, :name, area_id),
        include_blank: "— none —", class: "simple-select2" %>
<% end %>
```

In the controller, add to the attribute hash:

```ruby
area_id: params[:area_id].presence   # "" becomes nil, which detaches the budget
```

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/budgets_controller_test.rb'`
Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/reimbursements/budgets app/controllers/admin/reimbursements/budgets_controller.rb \
        test/functional/admin/reimbursements/budgets_controller_test.rb
git commit --no-verify -m "feat(reimbursements): move a budget between areas from its own form

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Group the budgets index by area

**Files:**
- Modify: `app/views/admin/reimbursements/budgets/index.html.erb`, `app/controllers/admin/reimbursements/budgets_controller.rb:20-33`
- Test: `test/functional/admin/reimbursements/budgets_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
test "the index groups budgets under their area and lists the rest separately" do
  area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
  create_reimbursements_budget(name: "Cogito: Marketing", area: area, initial_budget: 400)
  create_reimbursements_budget(name: "Contingency", initial_budget: 1_000)

  get :index

  assert_response :success
  assert_select "[data-area='#{area.record_id}']" do
    assert_select "td", text: /Cogito: Marketing/
  end
  assert_select "[data-area='none']" do
    assert_select "td", text: /Contingency/
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/budgets_controller_test.rb -n /groups/'`
Expected: FAIL — no matching element.

- [ ] **Step 3: Implement**

In the controller, group the already-loaded list rather than issuing new queries
(the store memoizes and these collections are tens of rows):

```ruby
@budgets_by_area = store.budgets_with_actuals.group_by(&:area)
```

**`budgets_with_actuals` must preload `:area` or this N+1s** — one query per
budget to draw a grouping header. Add `:area` to its `includes` in
`DatabaseStore#budgets_with_actuals` (Task 6 touched the same method's
neighbours), and to `#budgets` for the same reason: `Budget#owners` now asks the
area for them, so every unpreloaded budget costs a query the moment anything
reads an owner.

In the view, render one section per area — its name, its `projected_amount`,
`allocated` and `committed_amount` — then a final section for the `nil` key
headed "Not in an area". **Render an area's `remaining` only when it is
non-nil**, and show `unallocated` as "not yet allocated", never as money spare.

- [ ] **Step 4: Run the tests**

Run: `flock /tmp/bl-test.lock -c 'bin/rails test test/functional/admin/reimbursements/budgets_controller_test.rb'`
Expected: PASS, whole file.

- [ ] **Step 5: Verify it in the browser**

Start the dev server (`bin/dev`, checking the port is free first) and open
`/admin/reimbursements/budgets`. Confirm the grouping reads correctly with an
area that has no agreed total, and take a screenshot. Stop `bin/dev` before
running system tests — a running dev server fails ~57 unrelated ones.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/reimbursements/budgets app/controllers/admin/reimbursements/budgets_controller.rb \
        test/functional/admin/reimbursements/budgets_controller_test.rb
git commit --no-verify -m "feat(reimbursements): group the budgets index by area

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Close out phase 1

- [ ] **Step 1: Full suite and system tests**

```bash
docker start mysql8
flock /tmp/bl-test.lock -c 'bin/rails test'
flock /tmp/bl-test.lock -c 'bin/rails test:system'
```
Expected: 0 failures, 0 errors on both. Paste the real counts into the report.

- [ ] **Step 2: The CI-equivalent gate**

```bash
hk run check --from-ref <base-sha> --to-ref HEAD
```
Plain `hk run check` only scans the working diff and proves nothing.

- [ ] **Step 3: Document only the traps in CLAUDE.md**

Terse bullets in the reimbursements section, no feature narration: that the
area owns and budgets inherit (and that budget-owner rows are kept but do not
apply); that a forecast belongs to exactly one of the two; that `remaining` and
`unallocated` are nil rather than wrong when nothing was agreed; that the
backfill is a service, not migration code, because test databases are
schema-loaded.

- [ ] **Step 4: Commit and report**

Report: what changed, the observed counts, every decision the plan left open and
what you chose, and the migrations awaiting the user's approval before merge.
