# Areas: grouping a show's spend across nominal codes

**Status:** design, awaiting review. Decision and its evidence: [plans/area-grouping-options.md](../../../plans/area-grouping-options.md).
**Decided:** Option D — an `Area` above budgets, with a budget line found-or-created on demand.

## The problem

A budget carries one nominal code and one figure, so a show that spends under more than one
heading needs more than one budget — and once it does, its spend cannot be seen together, given a
single total, or given a single owner.

Both cost centres have already invented a workaround for the missing concept, in different
shapes:

- **Fringe** puts it in the budget *name*: 17 of its 31 budgets read `Area: Category`
  (`BF Marketing: Correx Boards`, `Improverts: Retreat`, `Cogito: Marketing`). The other 14 are
  genuine standalone overheads — payroll, NI, Contingency, PRS/PPL.
- **Termtime** puts it in the *sheet*: `Semester 1 Shows`, `Committee Budgets`,
  `Subcommittee Budgets`, `Utilities` all import with a name and no amount, because they are
  section headers with their lines beneath. The importer discards that structure.

Note also that a show's `Marketing` and `Other` lines carry the **same** nominal code (`432320`
for all of Cogito, Last Orders and Improverts). The category axis is Bedlam's, is finer than
EUSA's chart of accounts, and lives only in the budget name today. Anything that replaces the
budget with a per-transaction code loses it — which is why the code stays on the budget.

## Data model

```mermaid
erDiagram
    COST_CENTRE ||--o{ AREA : "funds"
    FINANCIAL_YEAR ||--o{ AREA : "scopes"
    AREA ||--o{ BUDGET : "groups (nullable)"
    AREA ||--o{ AREA_OWNER : "owned by"
    AREA_OWNER }o--|| PERSON : "is"
    BUDGET ||--o{ EXPENSE : "charged"
    BUDGET ||--o{ BUDGET_OWNER : "owned by (only when area-less)"
    COST_CENTRE ||--o{ NOMINAL_CODE : "labels"
    BUDGET }o--o| NOMINAL_CODE : "by code string, no FK"
    AREA ||--o{ BUDGET_FORECAST : "revises the total"
    BUDGET ||--o{ BUDGET_FORECAST : "revises the allocation"
    BUDGET_UPDATE ||--o{ BUDGET_FORECAST : "one meeting, both kinds"

    AREA {
        string name "matched within (year, centre)"
        decimal initial_budget "AUTHORITATIVE, nullable"
        bigint cost_centre_id
        bigint financial_year_id
        boolean active
    }
    BUDGET {
        string name "the category"
        string nominal_code "unchanged, EUSA-facing"
        decimal initial_budget "now OPTIONAL"
        bigint area_id "nullable"
    }
    NOMINAL_CODE {
        bigint cost_centre_id
        string code "unique within a centre"
        string label "means different things per centre"
    }
    BUDGET_FORECAST {
        decimal amount
        bigint budget_id "nullable"
        bigint area_id "nullable - exactly one of the two"
        bigint budget_update_id
    }
```

`Reimbursements::Area` — `name`, `cost_centre_id`, `financial_year_id`, `initial_budget`,
`notes`, `active`. Matched **by name within one (financial year, cost centre)**, the same rule
`BudgetImport` already uses for budgets, so an area recurs each year the way a budget does.

`Budget` gains `area_id`, nullable. A budget with no area behaves exactly as it does today — which
is what keeps the 14 standalone overheads, and every existing screen, working untouched.

**Nothing about the EUSA-facing structure moves.** The nominal code stays on the budget, so
`effective_nominal_code`, the BACS spreadsheet, the exports, and Reconcile's income match on
`budget.nominal_code` are all unchanged.

## Figures

**The area's figure is authoritative; a budget's is optional.** (Mick, 2026-09-10 — splitting an
agreed total across categories is sometimes not possible, and the schema should not demand it.)

`reimbursements_budgets.initial_budget` is *already* nullable, and the existing readers already
degrade honestly rather than lying: `projected_amount` is `current_forecast || initial_budget`,
`remaining` is nil without a forecast, and `variance` is nil if either side is nil. So "a line
with no agreed figure" needs no new handling — it needs the screens to stop implying one.

On the area:

| reader | meaning |
|---|---|
| `initial_budget` | the agreed total for the show. Nullable — the 7 backfilled areas start without one. |
| `committed_amount` | sum of its budgets' committed (Approved + Submitted + Paid, ex-VAT) |
| `remaining` | `initial_budget - committed_amount`, nil when there is no agreed total |
| `allocated` | sum of its budgets' `initial_budget`, skipping the nil ones |
| `unallocated` | `initial_budget - allocated` — how much of the total has not been split out |

`allocated` vs `initial_budget` is the drift worth showing: it says how much of the show's budget
has been assigned to categories, without pretending the remainder is spare.

**Expense and Income areas are never totalled together**, for the same reason budgets aren't
(`NominalCodeRollup#by_type`).

> **Amended 2026-09-11 (Mick's basis ruling, Phase 2b Task 5).** This section originally continued
> "An area holding both is an error worth reporting at import." It is not: an area holding both is
> a first-class state, and the area DECLARES what its agreed total is a total of
> (`areas.budget_basis` — a SHOW gets a spend cap, a COMMITTEE a net allowance). `expenses` leaves
> the income lines out of `Area#allocated`; `net` subtracts them. The first sentence still stands
> unchanged: `AreaRollup#by_type` keeps its two subtotals separate on BOTH bases, because "what
> did this area spend" is a different question from "how much room has it left".

## Ownership

**The area owns; its budgets inherit.** `Budget#owners` resolves to `area.owners` when the budget
has an area, and to its own `budget_owners` rows when it doesn't.

- New join `reimbursements_area_owners` (`area_id`, `person_id`, unique together), mirroring
  `reimbursements_budget_owners` exactly.
- `Reimbursements::OwnerReview` needs no change *if* `Budget#owner_ids` keeps its current
  contract (Person record-id strings). Resolve inside the model, not at every call site.
- **The backfill must seed each area's owners from the union of its children's**, or the seven
  new areas would own nothing and every claim under them would skip the owner gate silently. Few
  owners exist today (the 2026-07 UX review counted 26 of 31 budgets with none), so this is small
  — but "the gate quietly stopped applying" is the worst way to get it wrong.
- `budget_owners` rows on an area-bound budget are **kept, not deleted** — they are the record of
  who owned it before, and deleting them makes the backfill irreversible.

## Where areas come from

**An explicit `Area` column in the committee's spreadsheet** (Mick's choice over reading the
header rows). Matched by name within (year, cost centre); created when absent, exactly as budget
lines are.

- An optional **`Area Budget`** column supplies the area's authoritative total. Because a sheet
  has one row per budget line, that value repeats down the rows of an area — **two different
  values for one area is a blocking error**, not a last-one-wins. Consistent with the importer's
  existing rule that an unreadable amount blocks the import.
- `initial_budget` on an area is **write-once on create**, like a budget's, so a re-import logs a
  revision rather than rewriting the figure the committee agreed. See the open question below on
  where that revision is recorded.
### Managing areas by hand (v1)

The sheet is the normal route, but not the only one — the seven backfilled areas exist before any
sheet has an `Area` column, and a mis-filed line should not need a re-import to correct.

- **The area's edit form carries its budgets as nested fields**
  (`accepts_nested_attributes_for :budgets`, rendered through `shared/form/sections/_nested_fields`
  — and unlike `ticket_prices`, these are a real association, so no `template_object:` is needed).
  Add a line to an area, edit its name/code/figure, and detach one, all in one form.
- **A budget's own edit form gains an area picker**, so a line can be moved from the other
  direction. Both routes write the same `area_id`.
- Detaching a budget sets `area_id` to nil; it does not delete anything. A budget with no area
  behaves as it does today.

**A hand move is NOT silently reverted by the next import.** When the sheet's `Area` column
disagrees with a budget's current area, the import reports it as a **re-home** in the preview —
its own bucket, ticked by default, alongside create/revise/unchanged — rather than applying it
silently. This follows the importer's existing temperament: `absent_budgets` are reported and
never deleted, and an unplaced line is adopted rather than quietly shared. Somebody moved that
budget on purpose, and the sheet should have to say so out loud before undoing it.

## Find-or-create, and the nominal code list

A submitter picks their **area**, then a **category**. The category list is the area's existing
budgets, plus "another category…" which offers that cost centre's nominal codes by label. Picking
one creates `Budget(area:, nominal_code:, name: <label>, initial_budget: nil)` — a line with no
agreed figure, which reads on every screen as *unbudgeted spend within this area*.

`Reimbursements::NominalCode` — `cost_centre_id`, `code`, `label`, `active`; unique on
`(cost_centre_id, code)`. **Per centre, because the same code means different things in
different pots** (Mick, 2026-09-10). Seeded from the codes already in use per centre, labelled
from the budget names that carry them.

**Maintained on the cost centre's own edit page** (Mick, 2026-09-10) — `SettingsController`,
which is already the CostCentre CRUD under another name, and already the place its mailboxes,
EUSA code and nightly run-days live. Nested fields beside those, the same vocabulary as the area
form. **The list is owned by that centre's finance admin**, which is the answer to "who keeps it
current": the person who owns the pot owns its chart of accounts, and it sits on the page they
already visit to configure the centre.

Rules:

- **Creation is inside the same transaction as the claim**, and re-takes the find under a lock —
  the same hazard `DatabaseStore#create_expense_for_actual!` already guards, where a
  double-submitted form would otherwise create the line twice.
- A budget created this way is **flagged for finance** on the Review queue until someone with the
  finance permission has seen it. The claim is never held up; the line does not pass unseen.
- The producer picker still reads `active_budgets`' rules — an area whose cost centre is not the
  active year's is not offerable.

## Backfill

One migration, reversible, run per cost centre:

1. For each budget whose name matches `/\A(?<area>[^:]+):\s*(?<category>.+)\z/`, take the area
   name (stripped — `"Improverts:  Retreat"` has two spaces) and find-or-create the `Area` within
   that budget's (year, centre).
2. Point the budget at it. **Leave the budget's name alone** — renaming `Cogito: Marketing` to
   `Marketing` is a second, cosmetic change and would rewrite every screen's labels in the same
   step as the structural one. Do it later, or never.
3. Seed each area's owners from the union of its children's `budget_owners`.
4. Areas get no `initial_budget` — nobody agreed one.

Expected on today's data: **7 areas over 17 of Fringe's 31 budgets**; the other 14 stay area-less.
Termtime's 62 have no colon convention and get nothing until their sheet carries an `Area` column.

Down-migration drops `area_id`, the areas and the area owners; the `budget_owners` rows kept in
step 3 are what make that a true reverse.

## Screens and store readers

| surface | change |
|---|---|
| Budgets index | group rows under their area; area subtotal row; area-less budgets in their own section |
| Budgets overview | `NominalCodeRollup` unchanged (still by code). Add an area rollup beside it — the same `by_type` re-group mechanism |
| Budget new/edit | area picker; area figure and owners move to the area's own form |
| Producer submission | area → category picker, with "another category…" |
| Review | show the claim's area beside its budget; flag finance-unseen lines |
| Exports | an `Area` column in `Exports::Budgets` and `Exports::Expenses`, appended (a saved formula keeps pointing at the same column) |
| `DatabaseStore` | `areas`, `areas_for_year`, `areas_with_actuals`; `budgets*` readers gain `includes(:area)` |

**Scoping follows the rules already stated in CLAUDE.md**: `areas_for_year` is year- and
cost-centre scoped; anything that is an id→record lookup is not; nothing on the money path reads
a lenient filter.

## Testing

- Backfill: a budget with a colon, one without, one with a double space, one already in an area,
  and the owner-union step. Run the down-migration and assert the tree is gone and the
  `budget_owners` rows still stand.
- Ownership resolution: a budget in an area (inherits), one not (its own), and an area with no
  owners (gate does not apply) — asserted through `OwnerReview`, not just the model.
- Find-or-create: concurrent double submit creates one line, not two.
- Import: `Area` column creates and matches; two different `Area Budget` values for one area
  block the import; an area holding both Expense and Income budgets is reported.
- Figures: an area with no total, a line with no total, and drift between `allocated` and
  `initial_budget`.
- **A system test that clicks the real submit on the area→category picker**, per the two defects
  on 2026-09-10 that request-level tests could not see.

## Open questions for review

1. ~~Where is a revision to an area's total recorded?~~ **RESOLVED: a forecast attaches to
   either.** `budget_forecasts.budget_id` becomes nullable, `area_id` is added, and a check
   constraint requires exactly one of the two. `BudgetUpdate` is unchanged and groups both kinds,
   so one committee meeting stays one update.

   Mick asked whether forecasts should simply *become* area forecasts. They can't, and the
   production data is why: **14 of Fringe's 31 budgets have no area** — Hourly payroll, NI
   contributions, Consumables, PRS/PPL, Contingency — and they need revising like any other line.
   Contingency is the proof: it is the one budget Maysan's 2026-09-08 import revised. A
   pure area-level forecast log could only express that by inventing a single-child area for each
   of those 14 overheads, which is a fake grouping created to satisfy a table.

   The alternative of a parallel `area_forecasts` table was rejected for two reasons: `jscpd`
   gates duplication at 0 and the model would be a near-copy, and more importantly two forecast
   concepts drift — the day one gains a `reason` or an effective-date rule, the other won't.

   Both levels having a revision log is meaningful rather than redundant: an **area** forecast
   revises the show's agreed total, a **budget** forecast revises how much of it a category is
   allocated. `Budget#variance` keeps its current meaning untouched.
2. ~~Should the backfill rename `Cogito: Marketing` to `Marketing`?~~ **RESOLVED: yes, but as its
   own PHASE 2 migration, not in the backfill** (Mick, 2026-09-10).

   It cannot go in the Phase 1 backfill, because that shipped and runs on the next deploy. More
   importantly the two must stay separate for a reason worth stating: the backfill's `down`
   refuses when "an Area's name is not reproducible as the colon-prefix of at least one of its
   own budgets", and **renaming trips exactly that guard**. That is correct rather than a
   problem — once the prefix is stripped, the area's name is the only place the grouping lives,
   so the backfill genuinely cannot be unwound.

   The chain still reverses in order, which is why this works: the rename's own `down`
   reconstructs `"#{area.name}: #{budget.name}"` losslessly, and once it has, the backfill's
   `down` passes its guard again. So `db:rollback:primary STEP=n` unwinds rename → backfill
   correctly, and neither migration alone can leave the tree in a state the other refuses to
   touch.

   A budget with no area is never renamed. A name that does not start with its own area's name
   plus a colon is left alone (someone edited it by hand; that is not this migration's to
   rewrite).
3. ~~Who owns the nominal code list?~~ **RESOLVED: the cost centre's finance admin, maintained
   on the cost centre edit page** (Mick, 2026-09-10). See the section above.

4. ~~Does the area's `Area Budget` column belong in the sheet?~~ **RESOLVED: yes** (Mick,
   2026-09-10). The committee agrees a show's total in the spreadsheet, so that is where it comes
   from; the area form edits it afterwards. It repeats down the rows of an area, and **two
   different values for one area is a blocking error**, not last-one-wins — consistent with the
   importer's rule that an unreadable amount stops the whole import. Write-once on create, like a
   budget's `initial_budget`, so a re-import logs a revision rather than rewriting the agreed
   figure.

5. ~~Whom does the sheet's owner column name when a line has an area?~~ **RESOLVED: the AREA**
   (Mick, 2026-09-10) — "once there's an area the owner of a budget line is moot and we only look
   at the area", which is exactly what `Budget#owners` does. So the importer syncs the **area's**
   owners for a line that has one, and the budget's own rows only for a line that does not. This
   is what closes the half-fix Phase 1 left behind, where the sheet's named owner landed on rows
   nobody reads and got no sign-off gate.

   **One consequence needs a rule, and I am taking the union unless overruled:** the sheet has one
   owner column per LINE, so three lines under "Cogito" can name three different people. The
   area's owners become the **union** of what its lines name. That matches what the Phase 1
   backfill already did when seeding an area from its children, and it is the forgiving
   direction — any one owner satisfies the gate, so an extra owner can endorse while a missing one
   strands the claim. The cost is that a stale name on one line quietly gains sign-off authority
   over the whole show, which is why the preview must SHOW the resulting owner set per area rather
   than only counting syncs.

## Out of scope

- Linking an area to the main app's `Event`. There is currently zero linkage between the
  reimbursements module and the show domain, in either direction. An area is the natural place a
  future `belongs_to :event` would hang — do not design it in a way that forecloses that, but do
  not build it.
- Renaming budgets (see open question 2).
- Areas spanning cost centres or financial years. A show is funded from one pot in one year.
