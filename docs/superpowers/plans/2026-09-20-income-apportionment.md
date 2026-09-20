# Income apportionment implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let finance split one EUSA credit row across several income budgets, so a single Stripe payout covering five shows lands on five budget lines instead of one.

**Architecture:** A new `reimbursements_actual_allocations` join table carries `(eusa_actual_id, budget_id, amount)`. An apportioned row clears its own `budget_id` — allocations become the single answer to "which budget is this row's income" — and every reader that used to ask `budget_id` learns to ask the allocations too. Apportionment operates only on credit rows that have already landed, so the parts are constrained to sum to the row's own net and no residual can exist.

**Tech Stack:** Rails 8.1, MySQL 8.4, minitest, Tailwind v4, Stimulus, Turbo.

**Spec:** This file. The design decisions were settled in conversation on 2026-09-20; the rationale is recorded inline under each task rather than in a separate spec document.

## Background: why this shape

Maysan (business manager) needs two things that look like one:

1. **Stripe arrives as one mass payment** that does not split per show. Today `reimbursements_eusa_actuals` carries a single `budget_id`, so a £4,000 payout covering five shows can only ever land on one line.
2. **Fundraised money is invisible between actuals exports.** This is NOT solved here. Expected income is recorded as an ordinary **budget forecast**, which the portal already supports and the overview already renders as variance against actuals. Confirm that path works for an Income budget as Task 0 and tell her; write no new code for it.

Rejected alternatives, so they are not re-proposed:

- **"Add Income as an expense type."** Asked for twice. Income is not a claim; it has no payee, no receipt and no approval path. It comes from the EUSA ledger.
- **Letting her log income early as a pseudo-actual, reconciled later.** This invents a second source of truth for money that has landed, and creates an "early figure disagrees with the actual" state that has to be resolved. Forecasts already occupy that role and never pretend the money arrived.
- **A residual / unallocated remainder.** Only needed if the parts are typed independently. They are not: apportionment divides the row, so the parts sum to it by construction.
- **Accounting for Stripe's processing fee.** Explicitly out of scope (Mick, 2026-09-20). The payout that lands is already net; if the fee is ever wanted as a cost it is its own expense line against a fees budget, not a piece of this.

## Global Constraints

- **Credit rows only.** A debit row is split by converting it into several expenses, which already works (`ActualsController#new_expense`). Apportioning debits would also have to reconcile with `Budget#debit_actual_total`, which totals through *expenses* rather than `budget_id` — a different mechanism. Do not widen this.
- **An offsetting leg is never apportionable**, mirroring `EusaActual#convertible_to_expense?`. It nets to zero, so apportioning it would invent income.
- **Rows are never deleted.** Finance needs the audit trail. Undo removes allocations and restores the row to unlinked.
- **Test/CI databases are schema-loaded, so a data migration never runs there.** Nothing in this plan may depend on migration-time data changes.
- **`jscpd` gates duplication at threshold 0.** Three tests repeating a setup block will fail the build — extract a helper into `test/support/reimbursements_test_helpers.rb`.
- **`bin/rails test` does not run system tests.** Run `bin/rails test:system` separately, and stop any `bin/dev` first or ~57 unrelated system tests fail.
- **Start the test database first:** `docker start /mysql8`.
- **Multi-database app:** rollback is `bin/rails db:rollback:primary STEP=n`, never bare `db:rollback`.
- **Money is parsed through `Reimbursements::AmountParser`.** `.parse!` distinguishes blank (nil) from unreadable (raises). Never hand a raw param string to an AR decimal column — `to_d` turns `"£1,200"` into `0`.
- **Every export cell goes through `Reimbursements::CellSanitizer`.**

## Review Focus

Five failure modes this design implies that no single task's happy path exercises. Each has its test named in the task that owns the code.

1. **An apportioned row that still carries `budget_id` double-counts.** The row's full value lands on the old budget AND its shares land on the allocated ones. Task 3 pins that apportioning clears `budget_id`, and Task 4 pins that a budget's total counts each row once.
2. **`unattributed_actuals` inverts into a false "all clear".** It rejects rows with a `budget_id`; an apportioned row has none, so without a change every apportioned row reappears on the overview's unlinked-spend safety card — and the card is the only thing stopping unlinked money disappearing. Task 5.
3. **Allocations that do not sum to the row.** £4,000 split into parts totalling £3,880 understates income by £120 with nothing on screen saying so. Task 3 refuses the write; Task 6 refuses the form.
4. **An allocation to a budget from another cost centre or financial year.** The picker is drawn from a scoped list while the write is unscoped — the exact shape of the area-select bug (`areas_for_year`). Task 6 validates the posted ids against the ids actually rendered.
5. **N+1 on the budgets overview.** Reading allocations per budget without a preload turns one page into a query per budget. Task 4 asserts a query count, as the area work did (10→36 vs 32→31).

---

## File Structure

**Create**
- `db/migrate/<ts>_create_reimbursements_actual_allocations.rb` — the join table.
- `app/models/reimbursements/actual_allocation.rb` — the row, its validations.
- `app/views/admin/reimbursements/actuals/apportion.html.erb` — the split form.
- `test/models/reimbursements/actual_allocation_test.rb`
- `test/services/reimbursements/apportion_actual_test.rb`
- `test/functional/admin/reimbursements/actuals_apportion_test.rb`
- `test/system/admin/reimbursements/actuals_apportion_js_test.rb`

**Modify**
- `app/models/reimbursements/eusa_actual.rb` — `allocations`, `apportionable?`, `apportioned?`.
- `app/models/reimbursements/budget.rb:247` — `credit_actual_total` counts allocations.
- `app/services/reimbursements/database_store.rb:257` — `unattributed_actuals`; new `apportion_actual!` / `remove_apportionment!`; preloads.
- `app/controllers/admin/reimbursements/actuals_controller.rb` — `apportion`, `create_apportionment`, `remove_apportionment`.
- `app/views/admin/reimbursements/actuals/index.html.erb` — the Apportion action and the apportioned badge.
- `config/routes.rb:213` — three member routes.
- `app/services/reimbursements/exports/actuals.rb` — an allocations column.
- `test/support/reimbursements_test_helpers.rb` — `create_reimbursements_eusa_actual` (does not exist yet).

---

## Task 0: Confirm the forecast path for income

**Files:** none (verification only).

- [ ] **Step 1:** Open an Income budget in the admin and add a forecast through the existing budget-update flow. Confirm it renders on the budgets overview beside the EUSA actual figure.
- [ ] **Step 2:** If it does, write one paragraph in `docs/reimbursements/mysql-migration-and-roadmap.md` under a new "Recording expected income" heading saying that expected fundraising is a forecast, not an actual, and why. If it does NOT work, stop and report — that changes the plan.

---

## Task 1: The allocations table

**Files:**
- Create: `db/migrate/<ts>_create_reimbursements_actual_allocations.rb`
- Create: `app/models/reimbursements/actual_allocation.rb`
- Test: `test/models/reimbursements/actual_allocation_test.rb`

**Interfaces:**
- Produces: `Reimbursements::ActualAllocation` with `eusa_actual_id`, `budget_id`, `amount` (BigDecimal, positive).

Both parent tables have **bigint** primary keys, so plain `t.references` is right here. (The legacy integer-PK trap applies to `opportunities` and friends, not to these.)

Declare the index **inside** `create_table`. A standalone `add_index` beside a foreign key makes `create_table` irreversible, and this plan requires the rollback to actually run.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Reimbursements::ActualAllocationTest < ActiveSupport::TestCase
  test "requires a positive amount" do
    allocation = Reimbursements::ActualAllocation.new(amount: 0)
    assert_not allocation.valid?
    assert allocation.errors[:amount].present?
  end

  test "a budget appears at most once per actual" do
    actual = create_reimbursements_eusa_actual(credit: 100)
    budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
    Reimbursements::ActualAllocation.create!(eusa_actual: actual, budget: budget, amount: 40)
    duplicate = Reimbursements::ActualAllocation.new(eusa_actual: actual, budget: budget, amount: 60)

    assert_not duplicate.valid?
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

`docker start /mysql8 && bin/rails test test/models/reimbursements/actual_allocation_test.rb`
Expected: FAIL — uninitialized constant, and `create_reimbursements_eusa_actual` undefined.

- [ ] **Step 3: Add the test helper**

In `test/support/reimbursements_test_helpers.rb`, following the shape of `create_reimbursements_budget`:

```ruby
def create_reimbursements_eusa_actual(nominal_code: "4100", narrative: "Stripe payout",
                                      debit: nil, credit: nil, date: Date.current,
                                      cost_centre: nil, **attrs)
  Reimbursements::EusaActual.create!(
    nominal_code: nominal_code, narrative: narrative,
    debit: debit, credit: credit,
    net: (debit || 0) - (credit || 0),
    date: date, period: "06", source_month: "2026-09",
    cost_centre: cost_centre, **attrs
  )
end
```

- [ ] **Step 4: Write the migration**

```ruby
class CreateReimbursementsActualAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :reimbursements_actual_allocations do |t|
      t.references :eusa_actual, null: false, type: :bigint,
                   foreign_key: { to_table: :reimbursements_eusa_actuals }
      t.references :budget, null: false, type: :bigint,
                   foreign_key: { to_table: :reimbursements_budgets }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
      t.index %i[eusa_actual_id budget_id], unique: true,
              name: "index_reimb_actual_allocations_on_actual_and_budget"
    end
  end
end
```

- [ ] **Step 5: Write the model**

```ruby
module Reimbursements
  ##
  # One budget's share of a single EUSA credit row.
  #
  # +amount+ is POSITIVE and unsigned: the row's own direction says whether it
  # is income or spend, and a negative money figure means bad news everywhere
  # else in this portal. The shares of one row must sum to that row's absolute
  # net, which no per-row validation can see — DatabaseStore#apportion_actual!
  # owns that invariant.
  class ActualAllocation < ApplicationRecord
    self.table_name = "reimbursements_actual_allocations"

    belongs_to :eusa_actual, class_name: "Reimbursements::EusaActual"
    belongs_to :budget, class_name: "Reimbursements::Budget"

    validates :amount, numericality: { greater_than: 0 }
    validates :budget_id, uniqueness: { scope: :eusa_actual_id }
  end
end
```

- [ ] **Step 6: Migrate, run the test, and prove the rollback works**

```bash
bin/rails db:migrate
bin/rails db:rollback:primary STEP=1
bin/rails db:migrate
bin/rails test test/models/reimbursements/actual_allocation_test.rb
```
Expected: PASS, and the rollback completes without error.

- [ ] **Step 7: Commit**

```bash
git add db/ app/models/reimbursements/actual_allocation.rb test/
git commit -m "feat(reimbursements): a table for one budget's share of an actual"
```

---

## Task 2: Which rows can be apportioned

**Files:**
- Modify: `app/models/reimbursements/eusa_actual.rb:118`
- Test: `test/models/reimbursements/eusa_actual_test.rb`

**Interfaces:**
- Consumes: `ActualAllocation` from Task 1.
- Produces: `EusaActual#allocations`, `#apportionable?`, `#apportioned?`, `#allocated_total`.

- [ ] **Step 1: Write the failing tests**

```ruby
test "a credit row with no links is apportionable" do
  assert create_reimbursements_eusa_actual(credit: 4000).apportionable?
end

test "a debit row is not apportionable" do
  assert_not create_reimbursements_eusa_actual(debit: 4000).apportionable?
end

test "an offsetting leg is never apportionable" do
  actual = create_reimbursements_eusa_actual(credit: 4000, reconciliation_status: "offset")
  assert_not actual.apportionable?
end

test "a row already attached to a budget is not apportionable" do
  budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
  actual = create_reimbursements_eusa_actual(credit: 4000, budget: budget)
  assert_not actual.apportionable?
end
```

- [ ] **Step 2: Run them and watch them fail**

`bin/rails test test/models/reimbursements/eusa_actual_test.rb`
Expected: FAIL — `NoMethodError: apportionable?`.

- [ ] **Step 3: Implement**

```ruby
has_many :allocations, class_name: "Reimbursements::ActualAllocation",
         foreign_key: :eusa_actual_id, dependent: :destroy

# Splittable across several income budgets: a credit that landed, attached to
# nothing yet, and not an offsetting leg. Debits are split by converting them
# into several expenses instead (see #convertible_to_expense?), because a
# debit's budget figure totals through EXPENSES rather than through budget_id.
def apportionable?
  credit.present? && credit.positive? &&
    self[:budget_id].blank? && self[:expense_id].blank? && !offset?
end

def apportioned? = allocations.any?

def allocated_total = allocations.sum { |allocation| allocation.amount || 0 }
```

- [ ] **Step 4: Run and confirm PASS. Step 5: Commit.**

```bash
git commit -am "feat(reimbursements): say which actuals rows can be split"
```

---

## Task 3: Writing and undoing an apportionment

**Files:**
- Modify: `app/services/reimbursements/database_store.rb`
- Test: `test/services/reimbursements/apportion_actual_test.rb`

**Interfaces:**
- Produces: `DatabaseStore#apportion_actual!(actual_id, allocations)` where `allocations` is `[{ budget_id:, amount: BigDecimal }]`; `#remove_apportionment!(actual_id)`. Raises `DatabaseStore::NotApportionableError` and `DatabaseStore::ApportionmentMismatchError`.

Both write in ONE transaction and re-take the guard under a row lock, exactly as `create_expense_for_actual!` does — the controller's check is a read that goes stale on a double-submitted form, and a half-written apportionment leaves the row reading as unlinked while its shares are already on budgets.

- [ ] **Step 1: Write the failing tests**

```ruby
require "test_helper"

class Reimbursements::ApportionActualTest < ActiveSupport::TestCase
  setup do
    @store = Reimbursements::DatabaseStore.new
    @actual = create_reimbursements_eusa_actual(credit: 4000)
    @a = create_reimbursements_budget(name: "Show A", budget_type: "Income")
    @b = create_reimbursements_budget(name: "Show B", budget_type: "Income")
  end

  test "splits a row into shares that sum to it" do
    @store.apportion_actual!(@actual.id, [
      { budget_id: @a.id, amount: BigDecimal("2500") },
      { budget_id: @b.id, amount: BigDecimal("1500") }
    ])

    assert_equal 2, @actual.reload.allocations.count
    assert_nil @actual[:budget_id]
  end

  test "refuses shares that do not sum to the row" do
    assert_raises(Reimbursements::DatabaseStore::ApportionmentMismatchError) do
      @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("3880") } ])
    end
    assert_empty @actual.reload.allocations
  end

  test "refuses a row that is not apportionable" do
    debit = create_reimbursements_eusa_actual(debit: 500)
    assert_raises(Reimbursements::DatabaseStore::NotApportionableError) do
      @store.apportion_actual!(debit.id, [ { budget_id: @a.id, amount: BigDecimal("500") } ])
    end
  end

  test "removing an apportionment restores the row to unlinked" do
    @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("4000") } ])
    @store.remove_apportionment!(@actual.id)

    assert_empty @actual.reload.allocations
    assert @actual.apportionable?
  end
end
```

- [ ] **Step 2: Run and watch them fail.** Expected: `NoMethodError: apportion_actual!`.

- [ ] **Step 3: Implement**

```ruby
class NotApportionableError < StandardError; end
class ApportionmentMismatchError < StandardError; end

# Splits one credit row across several income budgets as ONE unit.
#
# The row's own budget_id is CLEARED: allocations become the single answer to
# "whose income is this", and a row holding both would have its full value
# counted on the old line AND its shares counted on the new ones.
#
# The guard is re-taken under a row lock because the controller's check is a
# read that goes stale on a double-submitted form.
def apportion_actual!(actual_id, allocations)
  EusaActual.transaction do
    actual = EusaActual.lock.find(actual_id)
    raise NotApportionableError unless actual.apportionable?

    total = allocations.sum { |allocation| allocation[:amount] }
    raise ApportionmentMismatchError unless total == actual.net.abs

    allocations.each do |allocation|
      ActualAllocation.create!(eusa_actual_id: actual.id,
                               budget_id: allocation[:budget_id],
                               amount: allocation[:amount])
    end
    actual.update!(budget_id: nil, reconciliation_status: "apportioned")
  end
  bust_eusa_actuals!
  bust_budgets!
  EusaActual.find(actual_id)
end

def remove_apportionment!(actual_id)
  EusaActual.transaction do
    actual = EusaActual.lock.find(actual_id)
    actual.allocations.destroy_all
    actual.update!(reconciliation_status: nil)
  end
  bust_eusa_actuals!
  bust_budgets!
  EusaActual.find(actual_id)
end
```

- [ ] **Step 4: Run and confirm PASS. Step 5: Commit.**

```bash
git commit -am "feat(reimbursements): split an actual across budgets in one unit"
```

---

## Task 4: A budget counts its shares

**Files:**
- Modify: `app/models/reimbursements/budget.rb:247`
- Modify: `app/services/reimbursements/database_store.rb` (`budgets_with_actuals` preload)
- Test: `test/models/reimbursements/budget_test.rb`

**Interfaces:**
- Consumes: `ActualAllocation` (Task 1), `apportion_actual!` (Task 3).
- Produces: `Budget#eusa_actual_amount` including allocated shares.

- [ ] **Step 1: Write the failing tests**

```ruby
test "an income budget counts its share of an apportioned row" do
  budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
  other  = create_reimbursements_budget(name: "Show B", budget_type: "Income")
  actual = create_reimbursements_eusa_actual(credit: 4000)
  Reimbursements::DatabaseStore.new.apportion_actual!(actual.id, [
    { budget_id: budget.id, amount: BigDecimal("2500") },
    { budget_id: other.id,  amount: BigDecimal("1500") }
  ])

  assert_equal BigDecimal("2500"), budget.reload.eusa_actual_amount
end

test "a fully linked row is counted once, not twice" do
  budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
  create_reimbursements_eusa_actual(credit: 900, budget: budget)

  assert_equal BigDecimal("900"), budget.reload.eusa_actual_amount
end

test "the overview does not query per budget" do
  store = Reimbursements::DatabaseStore.new
  3.times { |i| create_reimbursements_budget(name: "Show #{i}", budget_type: "Income") }

  budgets = store.budgets_with_actuals
  queries = count_queries { budgets.each(&:eusa_actual_amount) }

  assert_equal 0, queries, "eusa_actual_amount must read preloaded allocations"
end
```

If `count_queries` does not exist, add it to `test/support/reimbursements_test_helpers.rb` using `ActiveSupport::Notifications.subscribed` on `sql.active_record`, ignoring `SCHEMA` and `TRANSACTION` statements.

- [ ] **Step 2: Run and watch them fail.**

- [ ] **Step 3: Implement**

```ruby
has_many :actual_allocations, class_name: "Reimbursements::ActualAllocation"

# Income booked against this line: the rows attached to it whole, PLUS this
# line's share of any row that was split across several budgets. An apportioned
# row carries no budget_id (DatabaseStore#apportion_actual! clears it), so the
# two sets never overlap and nothing is counted twice.
def credit_actual_total
  -EusaActual.net(eusa_actuals.to_a) + allocated_credit_total
end

def allocated_credit_total
  if actual_allocations.loaded?
    actual_allocations.sum { |allocation| allocation.amount || 0 }
  else
    actual_allocations.sum(:amount)
  end
end
```

Then add `:actual_allocations` to the preload in `budgets_with_actuals` and to the `budgets:` preload inside `DatabaseStore#areas`. Miss the second and every area card N+1s.

- [ ] **Step 4: Run and confirm PASS. Step 5: Commit.**

```bash
git commit -am "feat(reimbursements): an income line counts its share of a split row"
```

---

## Task 5: The unlinked-spend card still tells the truth

**Files:**
- Modify: `app/services/reimbursements/database_store.rb:257`
- Test: `test/services/reimbursements/database_store_test.rb`

This is the most dangerous task in the plan. `unattributed_actuals` is what stops unlinked money disappearing, and it works by rejecting rows that carry a `budget_id` — which an apportioned row no longer does.

- [ ] **Step 1: Write the failing test**

```ruby
test "an apportioned row is not reported as unattributed" do
  store  = Reimbursements::DatabaseStore.new
  budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
  actual = create_reimbursements_eusa_actual(credit: 900)
  store.apportion_actual!(actual.id, [ { budget_id: budget.id, amount: BigDecimal("900") } ])

  assert_not_includes Reimbursements::DatabaseStore.new.unattributed_actuals.map(&:id), actual.id
end
```

- [ ] **Step 2: Run and watch it fail** — the row comes back as unattributed.

- [ ] **Step 3: Implement**

```ruby
def unattributed_actuals
  eusa_actuals_for_cost_centre
    .reject { |a| a.offset? || a[:expense_id].present? || a[:budget_id].present? || a.apportioned? }
    .sort_by { |a| [ a.nominal_code.to_s, a.date || Date.new(0), a.id ] }
end
```

Add `:allocations` to the preload behind `eusa_actuals_for_cost_centre`, or `apportioned?` fires a query per row on a page that renders hundreds.

- [ ] **Step 4: Run and confirm PASS. Step 5: Commit.**

```bash
git commit -am "fix(reimbursements): a split row is attributed, not unlinked"
```

---

## Task 6: The screen

**Files:**
- Modify: `config/routes.rb:213`, `app/controllers/admin/reimbursements/actuals_controller.rb`, `app/views/admin/reimbursements/actuals/index.html.erb`
- Create: `app/views/admin/reimbursements/actuals/apportion.html.erb`
- Test: `test/functional/admin/reimbursements/actuals_apportion_test.rb`, `test/system/admin/reimbursements/actuals_apportion_js_test.rb`

Routes, beside the existing `link_expense` / `confirm_link` pair:

```ruby
get :apportion
post :create_apportionment
post :remove_apportionment
```

House rules this screen must obey, each of which has cost this codebase a bug before:

- **The submit button sits in a `CardComponent` footer slot, so `form_with` must wrap the card, not the other way round.** A form opened inside the card renders its submit outside the `<form>` and the button silently does nothing. A request test cannot see this; only the browser test can.
- **Validate the posted budget ids against the ids actually rendered**, not against `active_budgets` re-read at POST time — the same rule `ExpenseForm#offerable_budget_ids` follows.
- **A select Tom Select takes over carries only `simple-select2`** and no border/width classes.
- **Capybara's `select` cannot drive those selects.** Click `.ts-control`, then the `.ts-dropdown-content .option` — see `tom_select` in `test/system/admin/reimbursements/producer_js_test.rb`.
- **Budget labels use the picker label** (cost-centre short code + display name) being added on the `finance-import-guards` branch. If that has merged, use it; if not, use `display_name` and leave a note.

- [ ] **Step 1: Write the failing functional test** covering: the form renders for an apportionable row; a POST whose parts sum correctly creates the allocations and redirects with a notice; a POST whose parts do not sum re-renders the form with an error and writes nothing; a POST naming a budget the form did not offer is refused.

- [ ] **Step 2: Write the failing system test** covering: the running total updates as amounts are typed, the submit is disabled while the parts do not sum to the row, and clicking the real submit button writes the allocations. The disabled-submit assertion is what proves the button is inside the form.

- [ ] **Step 3: Run both and watch them fail.**

- [ ] **Step 4: Implement the controller, view and a small Stimulus controller for the running total.** Amounts parse through `Reimbursements::AmountParser.parse!`; a blank row is dropped, an unreadable one is a blocking error naming the row.

- [ ] **Step 5: Run `bin/rails test` and `bin/rails test:system` and confirm PASS. Step 6: Commit.**

```bash
git commit -am "feat(reimbursements): split an EUSA credit across shows on screen"
```

---

## Task 7: Exports and the ledger row

**Files:**
- Modify: `app/services/reimbursements/exports/actuals.rb`, `app/views/admin/reimbursements/actuals/index.html.erb`
- Test: `test/services/reimbursements/exports/actuals_test.rb`

- [ ] **Step 1: Write the failing test** — an apportioned row's exported Budget cell names every budget and its share (e.g. `Show A £2,500.00; Show B £1,500.00`), and every cell still goes through `CellSanitizer`.
- [ ] **Step 2: Run and watch it fail. Step 3: Implement. Step 4: Run and confirm PASS.**
- [ ] **Step 5:** On the actuals index, an apportioned row shows a "Split" badge listing its shares, with a "Remove split" button beside it (finance-gated, as `unoffset` is).
- [ ] **Step 6: Commit.**

```bash
git commit -am "feat(reimbursements): a split row names its shares everywhere"
```

---

## Task 8: Documentation and close-out

- [ ] **Step 1:** Add a bullet block to `CLAUDE.md` under the Reimbursements portal section. Keep it to the traps only — the house style is short. Cover: credit rows only and why; apportioning clears `budget_id`; `unattributed_actuals` must exclude apportioned rows; both preloads.
- [ ] **Step 2:** Run the FULL suite (`bin/rails test` then `bin/rails test:system`) and `hk run check`.
- [ ] **Step 3:** Report back rather than merging. This touches the money path and the rollup arithmetic, so it wants a second look.
