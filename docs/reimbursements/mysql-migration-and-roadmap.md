# Reimbursements: MySQL migration and post-cutover roadmap

Authoritative, session-independent plan for cutting the reimbursements data over from
Airtable to MySQL, and the work that depends on that cutover. Written 2026-07-12 against
the `reimbursements-operator-tooling` branch (the current source of truth for the operator
tooling). The detailed schema/importer design lives in the companion doc
`docs/superpowers/specs/mysql-cutover-design.md` on the `phase-h-mysql` branch, but that
branch predates this session (it still carries the retired ActionMailer mailers, no
`draft_message_id`, and none of the money-safety work), so treat the schema there as a
reference and this doc as the current plan.

## Why cut over

- The Airtable free plan caps at roughly 1,000 API calls per month, shared across the portal
  and the operator tooling. Several known robustness fixes were deliberately deferred because
  they only matter on Airtable and disappear once the data is local.
- The data layer is POROs behind a cache-fronted `Store`, not ActiveRecord, so there is no
  referential integrity, no cheap multi-dimensional querying (year, cost centre), and no audit
  trail.
- Both the submitter portal and the operator tooling now run in Rails against the same Airtable
  base, so the data can move without a second consumer to coordinate (confirm Streamlit
  `bedlam-bacs` is retired first, see Phase G).

## The two seams that make this cheap

1. `Reimbursements::Store` is the single data gateway. Its public API (`expenses`, `budgets`,
   `update_expense!`, `set_expense_status`, batch/actual writes, cache busting) is what every
   controller and job calls. Swap its internals from the Airtable client to ActiveRecord and the
   callers barely change.
2. Airtable is addressed entirely by immutable field id through `Airtable::Config` / `Mapper`.
   The importer reads through that same mapping, so it never hard-codes a column name.

## Phase H: the cutover

> **Status (2026-07-17):** steps 1–4 and 6 are implemented on the
> `reimbursements-mysql-cutover` branch behind the `REIMBURSEMENTS_BACKEND` switch
> (default `airtable`; `database` = MySQL). The production flip follows
> [mysql-cutover-runbook.md](mysql-cutover-runbook.md); step 5 (deleting the Airtable
> layer) is a separate post-flip cleanup PR. Also shipped there: the mailbox
> idempotency key (`expenses.source_message_id`), the People email unique index,
> `budgets.cost_centre_id`, financial_years + FKs, and the
> `reimbursements_budget_owners` join table (owners are People, not a single FK).

Order is designed so each step is independently shippable and reversible.

1. **ActiveRecord models + migrations.** `Expense`, `Person`, `Budget`, `Batch`, `EusaActual`,
   and a **separate `PaymentDetails`** model (bank details kept out of `Person` per Mick).
   `CostCentre` is already ActiveRecord. Add `FinancialYear` and the join tables (see
   Multi-financial-year and Phase E below) in the same migration set even if their UI lands later,
   so the schema is right once. Use `strong_migrations`; the legacy integer-PK FK columns can't take
   a `t.references ... type: :integer` FK trivially (see `plans/off-topic-improvements.md`).
   The inert migrations on `phase-h-mysql` are a starting point but need refreshing against current
   fields (notably `Batch#draft_message_id`, the operator Expense fields, `Budget#owner_ids`).
2. **Importer** (`Reimbursements::AirtableImporter`, a one-shot idempotent job). Read every Airtable
   record via the existing client and map to DB rows. Re-runnable. Verify row counts and a checksum
   of amounts + statuses against Airtable before flipping. Keep `users.airtable_person_id`, then
   backfill a real FK.
3. **Store swap.** Replace the Airtable internals with ActiveRecord, keeping the public API. Point
   the portal writes at the DB too (it comes along for free through the same Store).
4. **Receipts / attachments.** Recommended: migrate Airtable attachments to ActiveStorage; or keep
   SharePoint as the archive and store the URLs. Airtable attachment URLs expire (~2h), so any
   migration must fetch fresh in one pass.
5. **Remove the Airtable layer.** Drop the PAT (`REIMBURSEMENTS_AIRTABLE_PAT`, via fnox/BWS today),
   the client, the 429 back-off, and the read-through cache. Remove the free-plan caching rationale.
6. **Drop `Batch#eusa_draft_created`** in favour of the already-added `draft_message_id` (a present
   id means the draft exists; nil means it doesn't), removing the redundant boolean.

**Definition of done:** import verified against Airtable counts + checksum; portal and tooling fully
green on MySQL; a batch built and a reconcile applied with **zero** Airtable calls; the Airtable base
decommissioned or made read-only.

## Deferred robustness items that the cutover resolves

These were skipped on purpose because they are Airtable-specific or need a stored key. Do them at or
just after the cutover.

- **Mailbox idempotency key.** Today the poll marks a message read first to avoid re-creating an
  expense on a failed move (mitigation only). The real fix stamps the source message id on the
  expense and skips if seen. Needs a column; free once on MySQL.
- **Per-cost-centre expense scoping.** Expenses currently have no cost-centre link, so the nightly
  and Build Batch operate on the global Approved set (fine while only Fringe F40 is live). Add
  `Budget belongs_to :cost_centre` so an expense resolves its centre via its budget; then scope the
  nightly alert, Build Batch, and Reconcile per centre. This is the `TODO(mysql)` in
  `nightly_batch_job.rb`. Required before a second cost centre (termtime BED) goes live.
- **Quota-only fixes become moot:** the AI-check cache-bust storm, cache dogpile on a miss, and the
  "serving stale backup data" banner all disappear when reads are local.
- **Atomic person find-or-create.** A DB unique index on People email removes the duplicate-People
  race in `PersonLink#ensure_person!`.

## Multi-financial-year (post-cutover)

A financial year is **orthogonal to cost centre**: Fringe (F40) recurs every year, and each year has
its own budgets, expenses, actuals, and P1–P12 reconcile periods. A budget is effectively
`(cost_centre, financial_year, name)`.

Decision (Mick, 2026-07-12): **one active year with occasional look-back** is enough. Do this
post-MySQL, not on Airtable (on Airtable the pattern is one base per year; if a new Fringe starts
before the cutover, spin up next year's base and swap the base-id config rather than build per-year
machinery).

Model:

- `financial_years` table: `label` ("Fringe 2026"), `starts_on`, `ends_on`, `active` (exactly one
  active). `budgets`, `expenses`, `eusa_actuals` each `belong_to :financial_year` (indexed FK).
  Backfill the imported year.
- **Active-year selector** in the finance nav. Every finance query scopes to the selected year;
  defaults to the active year; past years are viewable (read-mostly). This handles the year-boundary
  tail (reconciling last year's late payments while this year is live) without a full concurrent
  multi-year model.
- Reconcile periods (P1–P12) are scoped within the selected year.
- **"Clone into next year"** action: copy this year's budgets and per-year cost-centre setup so a new
  Fringe starts from last year's structure.
- Cross-year reporting becomes possible (compare Fringe 2026 vs 2027 spend).

### EUSA cost-centre codes

Not a table of their own. A code belongs to a cost centre, and Bedlam's codes have been stable, so
keep `eusa_code` on `CostCentre`. If a code ever needs to differ per year, add a thin
`financial_year_cost_centres` join (year × cost centre → `eusa_code`, and per-year run-days / mailboxes
if ever needed); the "clone into next year" action copies that row forward. Do not model EUSA codes as
a standalone entity.

## Phase E: budget-owner approval (post-cutover)

Deferred to after the cutover (Mick, 2026-07-12), where it is clean (no Airtable status-option add,
no Streamlit lockstep).

- New status **"Budget approved"** between `Pending` and `Approved` in `Reimbursements::Status`.
- **Budget Owner** role + a `:approve, :reimbursements_budget` grid permission.
- Budget↔owner is many-to-many. `Budget#owner_ids` already exists (a People link on Airtable today);
  on MySQL it becomes a `reimbursements_budget_owners` join table (`budget_id`, `owner_id`), **not** a
  single owner FK.
- `Admin::Reimbursements::ApprovalsController`: a budget owner sees only the Pending expenses on
  their budgets, and approves (→ Budget approved) or rejects (reason + Graph email).
- The business-manager Review queue then works the **Budget-approved** set: Pending → owner approves →
  finance reviews → Approved.
- Notify budget owners (Graph, from the send mailbox) on a new Pending expense on their budget.
- **Prerequisite:** budget owners must actually be populated in the data. Flagging budgets with no
  owner is worth doing now (it is in the current QoL batch) so the gap is visible before Phase E.

## Phase G: retire Streamlit

Once a full cycle (submit → approve → Build Batch → reconcile) has run in the Rails tool in
production: archive `bedlam-bacs` with a README pointer to BlackLightning, remove the
`deploy/systemd/` timer and the old nightly, and update BlackLightning `CLAUDE.md`. Confirm Streamlit
is fully retired before any Airtable status-enum change (Phase E), since a live Streamlit reading the
base would need the new status in lockstep.

## Sequencing

1. **Phase H** cutover (the big rock; ship the schema for financial year + cost-centre scoping + Phase E
   join tables in the same migration set).
2. **Multi-financial-year** UI + **per-cost-centre scoping** (schema shipped in H, wiring after).
3. **Phase E** budget-owner approval.
4. **Phase G** retire Streamlit.

## Open decisions / prerequisites

- Populate budget owners in the data (blocks Phase E usefulness).
- Confirm Streamlit is retired before any status-enum change.
- Receipts: ActiveStorage vs SharePoint-archive-plus-URLs.
- Refresh the `phase-h-mysql` inert migrations against the current field set before running them.
