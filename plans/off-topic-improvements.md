# Off-topic improvements

Open items noticed mid-task and parked. Each says what blocks it: a production data audit, a
decision from Mick, a change to another repo, or a live run against a third-party service.
Delete an entry when it ships.

**Settled, so don't re-raise:** a `Season` stays a schema.org `TheaterEvent` (Mick, 2026-09-06;
see the comment in `app/models/season.rb`).

## Database

### database_consistency: the schema-migration backlog (gate still advisory)

`database_consistency` is the one dev-env gate not yet at zero, so it stays advisory (`|| true` in
`hk.pkl` and `ci.yml`). The model-level findings are fixed (144 `length` validations) and the
legacy integer-PK checkers are scoped out in `.database_consistency.yml`. What remains (about 170
findings) is a real schema-migration project:

- `ColumnPresenceChecker` (101, add NOT NULL), `ForeignKeyChecker` (22, add FKs),
  `MissingUniqueIndexChecker` (21), `ThreeStateBooleanChecker` (15, NOT NULL boolean plus a
  default), and the remaining index checkers.
- These need **data-aware backfill migrations on the legacy production database**, whose columns
  may hold nulls or duplicates. `strong_migrations` rightly blocks them as unsafe, and they need a
  production data audit first. Do them as guarded multi-step migrations (backfill, then add the
  constraint), then drop the `|| true` so the gate enforces. The legacy integer-PK FK columns
  can't take a `t.references … type: :integer` FK trivially.

The two encrypted models add about 16 findings, mostly `LengthConstraintChecker` and
`UniqueIndexChecker`. `PaymentDetails#notes` is uncapped on purpose: it is an append-only audit
trail, and a cap would one day make a payee's bank details uneditable
(`test/models/reimbursements/encryption_test.rb` measures its headroom). A bounded log that trims
its oldest lines is the fix if that ever needs closing.

### The `reconciliation_status` index on eusa_actuals is never used by SQL

`index_reimbursements_eusa_actuals_on_reconciliation_status` has no SQL predicate behind it: every
offset filter runs in Ruby over the store's memoized list (`ActualsController#index`, `Budget`'s
rollups, `unattributed_actuals`). Left alone because dropping it needs a migration on the
production database, and it costs nothing at about 300 rows a financial year.

**Fix:** drop the index, or keep it and move the offset filters into SQL scopes
(`EusaActual.offset` / `.not_offset`).

## Reimbursements: areas and budgets

### Closing the area rename's rollback window (only on Mick's word)

`reimbursements_budgets.name_before_area_rename` is the only record of the `Area: ` prefix strip,
and `AreaRename.restore!` reads it. Dropping it makes the rename permanently irreversible. Do it
only when Mick says, in so many words, that rolling the rename back is off the table.

The migration must say so in its own body, because the next person reads that migration and
nothing else:

```ruby
# Dropping this column closes the area-prefix rename's rollback window FOR GOOD:
# AreaRename.restore! reads it to put back the exact strings #strip! took off,
# and raises MissingRecordError once it is gone. Only run this when rolling the
# rename back is no longer a decision anyone would make.
```

Explicit `up`/`down`. Prove that `down` re-adds the column and that `restore!` raises while it is
absent.

### A rollback past `20260911100600` forgets every area's basis

That migration's `down` drops `areas.budget_basis` and its `up` re-adds it with the `expenses`
default, so every net allowance comes back as a spend cap with nothing on screen to say so.
`area_before_rollback` cannot carry it: rollbacks run in descending version order, so the column
is gone before `AreaMembership.record!` runs, and a `STEP=1` rollback never runs that recorder at
all. Recording it needs a scratch column of its own. Until then, re-declare the net areas by hand
after any such rollback.

### A test that catches bare budget names (question for Mick)

Budget names are not unique since the prefix strip (production has three `Marketing` lines on one
nominal code), so every screen must name a budget through `Budget#display_name`. Four grep sweeps
each found sites the previous one missed. The mechanical fix is a test that seeds two identically
named budgets, walks every reimbursements screen, and fails on any bare name outside a rowgroup
heading. Expensive and not built: is it worth building?

### A claim cannot create its own budget line yet

The producer half of the area design was never built. As designed: a submitter picks an area,
then a category. The categories are the area's lines plus "another category…", which offers the
cost centre's nominal codes by label. Picking one creates
`Budget(area:, nominal_code:, name: <label>, initial_budget: nil)` inside the claim's transaction,
re-taking the find under a lock. A line made this way is flagged on the Review queue until someone
with the finance permission has seen it; the claim is never held up. The picker keeps
`active_budgets`' active-year rule.

The back end exists and nothing calls it: `Reimbursements::BudgetFinder`,
`DatabaseStore#find_or_create_budget_for_area!`, and `budget_finder_test.rb` /
`budget_finder_lock_test.rb`. **Question for Mick:** build the picker, or delete the unused code?

An area is also the natural place for a future `belongs_to :event`, tying a show's money to its
`Event`. Not built; don't design anything that rules it out.

### The area page's defaults were never confirmed

The area page shipped with three defaults Mick has not explicitly confirmed: "With EUSA" as a
label, pending claims counting against **Left**, and owners seeing every claim on their area.

### No export on My Budgets

Every finance list has a "Download CSV" and there is a combined workbook, but
`MyBudgetsController#index` (the owner-facing page, gated by base portal access rather than the
finance permission) has none. `Exports::Budgets` would work for the owned subset, but check the
columns first: an owner arguably shouldn't see another line's full rollups, and the exporter
assumes the finance-wide view.

### Budgets index is wider than a laptop

The action column is pinned, so Edit is reachable at 1366x768. The table is still wider than its
box (1218px of columns in a 1012px scrollport at 1366), so the pinned column covers the Remaining
cell until the operator scrolls right, clipping a money figure mid-word ("No bu… set"). The
underlying problem is 14 money columns. Fixes: a column-visibility control, Owners behind a
popover, or Pipeline/Paid moved to the overview.

### `Reimbursements::Area#income?` has no callers

`budgets.any?(&:income?)`, added with the model and never read. `debride` does not flag an AR
model's public reader, so it stays until someone deletes it.

## Reimbursements: claims, batches and reconciliation

### Should an unlinked EUSA credit attach to an *expense* budget? (decision)

`Reconciliation.match_credit_to_budget` only ever offers a credit row to **income** budgets, so a
supplier refund credited back on an expense nominal code has no path to its budget. Reconcile
leaves it unmatched and the overview's unattributed card shows it, but finance can't attach it.

`Budget#eusa_actual_amount` already nets a credit linked to one of the budget's expenses (a £300
refund on a £900 line reads £600), so the arithmetic is ready. The matching half is Mick's call:

- Matching by nominal code would be a guess wherever several budgets share a code, which is
  common, and a wrong guess silently understates one line and overstates another.
- The safer shape is an explicit operator action ("credit this refund to budget X"), or linking
  the credit to a specific *expense*, which is what the netting keys off.
- Either way, year-end accrual reversals also arrive as credits on expense codes and are usually
  better handled as offsetting pairs.

### Left over from the finance-UX pass (2026-09-21)

- **`Exports::Expenses` has no "Submitted by" column.** The screen separates "Paid to" (on an
  Invoice, the supplier) from "Submitted by"; the export carries only `Payee`. Append the column,
  so saved formulas keep pointing at the same columns.
- **Batch Detail has no `<h1>` and no Reopen.** Reopen lives on History while the contents live on
  Detail, so deciding to reopen and doing it are two screens apart.
- **`AmountValidation.error_for` names no field.** "Enter a valid amount excl. VAT greater than 0,
  or leave it blank." is a bare flash on a page with three amount fields.
- **Blanking the GBP amount on an international claim keeps the old figure.** The invoice amount
  clears on a deliberate blank (`DatabaseStore::CLEARABLE_EXPENSE_COLUMNS`); `amount` does not,
  because four other write paths rely on "nil means leave it alone". Clearing a GBP estimate needs
  its own decision.
- **The Actuals ledger prints bare nominal codes.** The budget form and the Overview show the
  labels finance maintains on Settings; the ledger does not.

### Switching a claim to the international rail and back loses its ex-VAT figure

`Expense`'s `before_validation` mirrors `amount_excl_vat` to the gross on the international rail,
and switching back to UK BACS on the finance edit form does not restore the split. Rare
(production has no international claims yet) and visible on the form. Fix: keep the UK figure
while the rail is international, or warn on the switch.

### `ExpenseForm#settled` is an invariant stated in prose, not enforced

It holds because nothing returns an unbatched claim to Approved: `revert_expense_to_approved!` is
only reached for a claim with a batch, and the finance edit form writes no `status`. The day a
"put this claim back in the queue" button writes `status: Approved` through
`store.update_expense!`, a settled Invoice imported without a payee trio pays the producer instead
of the supplier.

The obvious validation (refuse an Invoice at Approved with a blank trio) would also fire on
`revert_expense_to_approved!` for any legacy batched Invoice, breaking batch reopen. Run this in
production first:

    Reimbursements::Expense.where(expense_type: Reimbursements::Expense::TYPE_INVOICE,
                                  status: %w[Approved Submitted Paid])
                           .count { |e| e.payee_name_override.blank? }

If it is 0, scope the validation to `status_changed? && approved?` and ship it.
`ReviewSupport`/`approve_blocker` is the wrong home: it skips anything not Pending.

### Review and the finance edit form check budget existence only

`budget_record_id_error` answers "does this row exist", which suits the edit form (it offers the
inactive budget a claim is already on). Review's picker is `active_budgets`, so a budget
deactivated while the queue is open is still accepted there. Neither rescues
`DatabaseStore::BudgetGoneError`, so a delete inside the race window is a 500. Both are finance's
own screens, so nobody loses a claim. Review wants offerable ids or an `active` check; both want
the rescue.

### `owner_ids_error` has the same race

A Person deleted between a budget form being drawn and saved gets a pre-flight check and then an
unnamed foreign-key 500. A `PersonGoneError` (or a shared `LinkGoneError`) beside
`BudgetGoneError` would let the budget forms re-render. Not hit in production yet.

### Cost-centre scoping

- **`BudgetImport`'s cross-centre matching has no test of its own.** It matches names within one
  (year, centre) only because `budgets_for_year` is centre-scoped. Unscope that reader and the
  import silently matches across pots again. Worth a test naming the rule.
- **Batches have no `cost_centre_id` column.** Every reader derives a batch's centre from its
  expenses, which is exact today but goes stale when a reopen unlinks them and returns nothing
  for a batch whose expenses were deleted. Nullable column, backfilled from the expenses, then NOT
  NULL. Needs Mick's sign-off on the migration.
- **The finance Expenses list and Budget updates have no centre selector.** A `?cost_centre=` in
  their URL scopes `budgets_for_year` but not their own lists. Harmless but inconsistent. Reconcile
  is per row by design and must stay so.
- **`NightlyBatchJob` and the store answer "which centre owns an unplaced claim" differently**, on
  purpose: the reminder needs one recipient list, the filter does not. If a budget's cost centre
  ever becomes mandatory, collapse the two rules into one.

### Year scoping stops at the budget screens

Expenses, Review, Actuals, Batches and Reconcile still read every year. Reconcile periods within a
year and cross-year reporting (Fringe 2026 against 2027) were planned and never built.

### Review findings deferred on 2026-07-25

- **The People export carries every payee's name and email in the clear** while masking bank
  details. A deliberate call is wanted, not an omission.
- **Some export tests compare a header constant against itself**, so renaming a column passes.
  Only the Expenses headers are spelled out literally.
- **Tests mutate process-global ENV** and rely on `test_helper.rb` for the restore, and some
  row-count assertions break on any new fixture.

### The em-dash sweep (only if Mick asks)

About 71 user-facing prose sites in the reimbursements portal use an em dash, plus 6 bare `"—"`
empty-value glyphs where the helper convention is `"-"` (counted 2026-07-23). Mick stopped the
sweep on 2026-07-25: **do not relaunch it without Mick asking.**

## Imports

### `ImportParsing`'s categorisation helper is user-matching-specific

The concern's parsing half (`parse_data`, `parse_tsv`, `parse_xlsx`, `find_column`) is generic.
Its categorisation half is not: `build_categorized_result(multi_match_bucket:)` hardcodes
`:existing_user` / `:existing_users`, and `determine_bucket` is expected to return a `User`. So
`BudgetImport` and `ExpenseImport` each write their own `categorize`.

**Fix:** rename the payload key to something neutral (`:match` / `:matches`), let the including
class name its buckets, and move the two reimbursements imports onto it.

### `:canonical_tsv` is a marker `ImportParsing#parse_data` doesn't know

Both reimbursements wizards translate `:canonical_tsv` to `:paste` themselves
(`parse_data(data, @escaped ? :paste : input_type)`), because `parse_data` knows only `:paste`
and `:xlsx` and otherwise records "Unknown input type" and returns **zero rows**: a preview that
silently shows nothing. The concern owns the escaping, so it should own the input type too
(`when :paste, :canonical_tsv`). A third wizard that forgets the translation gets the empty
preview with nothing on screen to explain it.

### `escape_cell` applies to every cell, `unescape_cell` only to `TEXT_FIELDS`

Both wizards escape every column on the way out but unescape only `TEXT_FIELDS` on the way back,
so a backslash in any other column survives the preview doubled (`4\000` becomes `4\\000`).
Harmless today, since every other column is a parsed amount, date, enum or email and a stray
backslash already gets a row error. Escape only what is unescaped, or unescape everything.

### `ImportParsing#find_column`'s substring fallback

It matches any header *containing* a keyword, so on a wide sheet of near-anagrams ("Reference" /
"Payment reference") it reads the wrong column without a word. `ExpenseImport` and `BudgetImport`
have moved to `StrictColumnMatching`; the membership and user imports still use `find_column`.
Neither is known to be wrong (their sheets are narrow). Move the strict matcher into the concern
and put all four on it.

### The `import_key` comparison folds case but not accents

`ExpenseImport.key_match` downcases, but the column's `utf8mb4_unicode_ci` collation also folds
accents, so a sheet mixing `réf-1` and `ref-1` dead-ends at the unique index. Deliberate:
over-matching would drop a new claim silently. The apply rescue names renaming the reference as
the fix. The exact answer is to ask MySQL (`Expense.where(import_key: refs)`) instead of comparing
in Ruby.

### An imported expense is dated today unless the sheet dates it

`Expense`'s `before_create` stamps `submitted_at ||= Time.current`, so a 2019 claim imported
without a "Date submitted" column reads as submitted today. Harmless for terminal statuses, but
the expenses list then sorts as if the whole ledger arrived at once.

### The expense import writes UK BACS claims only

`ExpenseImport` has no `payment_method` column, so a historical international claim imports on
the wrong rail. Adding it means four more headings (IBAN, BIC, foreign amount, currency) for a
one-at-a-time case, so the normal form is the better route today.

### Every import wizard needs a Turbo Frame escape rule

A link inside a wizard's Turbo Frame needs `data: { turbo_frame: "_top" }` or it renders "Content
missing". All five links out of the budget import shipped broken that way. They are fixed and
tested, but nothing stops the next link. A herb rule, or a system test that walks every link
inside a `turbo_frame_tag` in these views, would.

### Vendor-file parsers are a separate family from the sheet importers

Worth naming before someone "unifies" them. **Sheet importers** (budget, expense, membership,
user, show crew) share `ImportParsing` and a preview-then-apply wizard, because a human makes
per-row decisions. **Vendor-file parsers** (`Reconciliation.parse_actuals_rows` for EUSA's Sage
export, `Climate::CsvImport` for Govee's) parse a fixed third-party format with stdlib CSV and
make no per-row decisions. Their hand-rolled CSV reading is mostly vendor quirks (Govee's BOM and
prose header; Sage's British dates and debit/credit columns), not duplication. A shared
`DelimitedFile` helper (BOM strip, delimiter sniff, header lookup) is worth it at three callers,
not two.

## Admin

### A Tom Select `<select>` carrying layout classes draws a box inside a box

`app/views/admin/debt_checkers/_user_lookup.html.erb` passes `class: "simple-select2 w-full"`,
against the rule in CLAUDE.md's Admin forms section. Sweep for other hand-written
`simple-select2` classes with width or border utilities (only hand-rolled `select_tag` /
`input_html:` cases can be wrong). Look at the page in a browser before changing it.

### The shared user picker is gated on an Event permission

`shared/form/_user_field.erb` defaults `all_users:` to `can?(:add_non_members, Event)`, described
in the grid as "Add non-members to events, mainly for archiving purposes". Five unrelated forms
render it (team-member credits, maintenance credits, staffing jobs, marketing-creatives profiles,
shared debt), so an event-archiving permission decides who is pickable on a staffing form. Rename
the permission, or have each caller pass the `all_users:` it needs (`_debt_form.erb` already
does). A permissions change, so Mick's call.

### Radio buttons render as squares

The `:vertical_collection` and `tailwind_horizontal_collection` wrappers apply
`FormStyles::CHECKBOX`, which carries `rounded`, to radio buttons too. So the area form's "Total
expenses / Total net" pair (and `application/_answer_fields`' Yes/No) renders as squares that
read as checkboxes. Fix: a `FormStyles::RADIO` (`rounded-full`) and a wrapper mapped for
`radio_buttons` only. It restyles every radio in the app.

### A disabled button looks live

`ButtonComponent::BASE_CLASSES` has no `disabled:` styling, so a disabled submit looks clickable
and does nothing. The apportion form works around it locally
(`disabled:opacity-50 disabled:cursor-not-allowed` plus resetting the primary hover). Adding that
to `BASE_CLASSES` is the real fix and restyles every button.

### `OpportunityRole#ordering` still goes through a hidden field

`sortable_controller.js#updateOrder` renumbers every row from 0, including rows already marked
for removal, and gives a newly added row no number until something is dragged. Team members no
longer use it (`TeamMemberOrdering` stamps the order from the posted row position). Opportunity
roles still do. The same server-side pattern would fix them: an `opportunity_roles_attributes=`
override stamping `ordering`, then drop the hidden field and the JS renumbering.

### The committee resources page has no link

`admin/static#committee` is routed and permission-gated, but nothing in the sidebar or dashboard
links to it. Add a sidebar entry gated on `can?(:access, :committee)`, or confirm the page is dead
and remove it.

### The pretix modal dialog is driven by two controllers

`shared/_pretix_modal.html.erb`'s `<dialog>` declares `data-controller="modal"` (for close and
backdrop close) while carrying `data-pretix-modal-target` attributes for the `pretix-modal`
controller on an ancestor, which calls `showModal()`. It works, but nothing in the partial says
so. Fold open/close into `pretix-modal`, or use a Stimulus outlet. Not urgent.

### Two dropzone implementations

The picture gallery uses Dropzone.js with ActiveStorage direct uploads into hidden fields the form
saves later. Receipts use a small Stimulus controller that posts to the server and streams the
gallery back. Both work. Unifying them means picking one upload model.

### The duplicates page can give two rows one DOM id

`admin/duplicates/index.html.erb` ids every row `pair-<a>-<b>` in every section, and the merge and
"not a duplicate" streams remove that id. A pair listed in two sections renders the id twice,
`turbo_stream.remove` takes only the first, and the second row stays offering an action on a
resolved pair. herb-lint 0.11.0's `html-no-duplicate-ids` flags it, which is why `hk.pkl` and
CI pin 0.10.4. Fix: remove by a class or data attribute, or remove every section's row. Then
unpin herb-lint.

### `expense_edits/edit.html.erb` trips `erb-no-duplicate-branch-elements`

Two non-gating herb hints: the `<div class="grid gap-4 sm:grid-cols-2">` wrapper repeats in both
branches of the UK/international conditional. Lift it out, after checking the rail-toggling
Stimulus controller (`data-rail-required`) still sees the same structure.

### `advance_review` on proposals has no tests and is labelled temporary

8f7afd98 / 7f36c1c9 add a grid permission letting holders read every proposal before the call's
deadline, with `cannot :advance_review, :proposals` ahead of the grid so an admin gets it only by
an explicit tick. No test covers either half. `"Advance Proposal Checker"` is in
`Role::HARDCODED_NAMES` though nothing asks for that role by name. The grid label says
"(temporary)": remove it, the two `Ability` blocks and the role name once the call closes.

### A rejected report attachment fails silently, after 30 minutes of retries

`ApplicationJob`'s `retry_on Net::SMTPServerBusy` (there for MailerSend's genuine 450 rate limits)
also retries a permanent 450 rejection, such as issue #169's "This file type is not supported" on
`ReportsMailer#send_report`, ten times over about 30 minutes. The requester, told the report "will
be emailed to you", hears nothing. `.xlsx` is accepted today, but any non-rate-limit 450 behaves
the same. Match the message (`file type`, `from.email must be verified`, `recipient is
suppressed`) to `discard_on`, and tell the requester when a report cannot be delivered.

## Public site and events

### SEO follow-ups that need something from outside the repo

- **No phone number exists to publish.** The footer carries the postal address on every page, two
  thirds of the Name/Address/Phone signal local search uses. If the box office has a public
  number, add it to the footer `<address>` and as `telephone` on `SchemaHelper::VENUE_ADDRESS`'s
  parent node. Never invent one.
- **Search Console and analytics are unverified.** No `google-site-verification` tag, no
  analytics tag, and no Google TXT record in DNS (only `MS=ms94671060`). Verification may exist
  through an uploaded HTML file: worth confirming. Until then none of the SEO work can be
  measured.

### Prices are per event, not per performance

A differently priced preview would need per-performance price overrides. No current show does
this. Prices are also typed in the admin: nothing syncs them from pretix.

### `Venue` has no capacity column

So nothing can emit `maximumAttendeeCapacity`.

### `display_price` reads oddly when one band is free and the others are not

The board's compact form joins the amounts ("£10/8/7"), and "Free" fires only when every band is
zero, so a paid standard band with a free members band prints "£10/0". Not wrong, but it reads
badly across a room. Left alone because the mixed case is rare and the obvious fixes either break
the compact convention or hide a band. Revisit if a real show prices this way.

### Heading anchors keep a slug built from the IAL text

commonmarker slugifies a heading from its raw source, so `## My Heading { .text-danger }` gets
`id="my-heading--text-danger-"`. An explicit `{ #my-anchor }` overrides it. Re-slugifying from the
cleaned text after `apply_ial` would **change existing anchor URLs** on any page with a class-only
IAL, so it needs a decision about breaking inbound links.

### The Active Storage representations override drops upstream's strict-loading blob scope

`ActiveStorage::Representations::RedirectController` (ours) subclasses
`ActiveStorage::BaseController` and includes `ActiveStorage::SetBlob`, instead of subclassing
upstream's `Representations::BaseController`. That skips upstream's `blob_scope`
(`ActiveStorage::Blob.scope_for_strict_loading`). **Fix:** subclass
`Representations::BaseController` and move the Vips/LoadError handling to a `rescue_from`, since
upstream processes in a `before_action` a method-level `rescue` can't reach. The Honeybadger
context call must then run before `set_representation`. Worth doing next time the file is open.

## Climate

### A dew-point-margin alert is the obvious next step

The dashboard shows the condensation-risk margin, but somebody has to look, and crypt damp does
its damage over days. **Fix:** a job that emails when a sensor's margin stays under
`ClimateHelper::CONDENSATION_RISK_MARGIN` for N consecutive hours. The readings and the margin
already exist.

Not planned: **wall temperature**, the honest fix for "this measures air, not stone", needs
hardware; **absolute humidity** was rejected because dew point already answers the question.

### The climate mailbox ingest is unverified end to end

`Climate::MailboxPollJob` is unit-tested against a fake mailbox but has never run against real
Graph: it needs the mailbox, the RBAC scope covering it, and Govee's scheduled export pointed at
it. Govee's email names no device, so `#sensor_for` uses the sole Govee sensor and otherwise
leaves the message unread with a deduped alert. More than one sensor needs a mailbox (or
plus-address) per sensor, resolved on the recipient.

### The Open-Meteo forecast tail is fetched and then discarded

`OutdoorPollJob` asks for `forecast_days=1` for self-heal margin, and `ReadingIngest` drops every
future row so a prediction is never drawn as an observation. Keeping them behind a flag as a
distinct dashed *forecast* segment past "now" would help with "should the dehumidifier run
tonight", but it must be unmistakable.

### No retention or rollup policy for `climate_readings`

About 52k rows per sensor per year at ten-minute polling, which MySQL won't notice for years.
There is deliberately no pruning: year-on-year comparison is the point. If the table passes a few
million rows, add an hourly or daily rollup table for long ranges rather than deleting history.
`SeriesQuery`'s bucketing is already that shape.

## Dev environment, CI and tests

### Loose ends from the mise move to `mise/`

- **`hk.pkl`'s `versions` step globs `mise.toml`**, which no longer exists, so a Ruby/Node bump in
  `mise/config.toml` may not trigger the drift guard. Test by bumping a version and committing.
  `hk.pkl`'s comments and `.devcontainer/Dockerfile.dev` / `setup.sh` still say `mise.toml` too.
- **`Procfile.dev` and the `foreman` gem are orphaned**: `bin/dev` was their only reader.
- The `dev-hooks:worktree-setup` script looks for a root `mise.toml` to trust and reports "No
  mise.toml, skipped mise trust" here. `mise trust` by hand works.

### Per-worktree databases are not seeded

`.worktree-isolate.conf` gives each worktree its own `PORT`, `VITE_RUBY_PORT` and
`WORKTREE_DB_SUFFIX`, and `config/database.yml` applies the suffix to the dev and test databases.
But a new worktree's databases don't exist until someone runs
`bin/rails db:prepare && bin/rails db:test:prepare`, and the dev one starts empty. The nice
version clones the main dev database (mysqldump into mysql) during provisioning.

Also worth doing: give each parallel subagent its own suffix. Two agents in one worktree still
share a test database, which is what the "serialise agent test runs" rule in the
`hk-stash-vs-background-agents` memory note is about. Update the
`parallel-worktree-dev-server-ports` note when that lands.

### A long worktree name overflows MySQL's identifier limit

The suffix comes from the worktree directory name and is appended to
`bedlam_blacklightning_development` (33 characters) plus `_queue`/`_cache` (6). MySQL caps
identifiers at 64, so a worktree name over about 25 characters provisions fine and then fails
`db:prepare` with "Identifier name '…' is too long". **Fix:** cap or hash the suffix in dev-hooks'
`isolate-worktree.sh` (every repo using it has the same ceiling), and/or note the limit in
`.worktree-isolate.conf`'s header.

### An intermittently flaky system test

`bin/rails test:system` failed about 1 run in 5 with a single error (2 of 8 runs, 2026-07-27),
not attributed to a test. Not parallelisation: system tests run on one worker. **Fix:** loop it
with full output until it reproduces
(`for i in $(seq 20); do bin/rails test:system > /tmp/sys-$i.log 2>&1; done`, then grep for
`^Error:` / `^Failure:`), name the test, and fix the race. Most likely a bare assertion racing a
Turbo or Stimulus render.

### CI setup time is apt-get update and an image pull

Measured 2026-07-27: `Install packages` 26 to 37s and `Initialize containers` 28 to 31s, unmoved by
dropping packages or tightening the MySQL health probe. So the time is `apt-get update` and the
mysql image pull. Levers if it matters: cache the apt lists, use the runner's preinstalled MySQL
instead of a service container, and cache the 11s `bin/vite build` on a source hash. Setup is
about 83s against about 100s of tests.

### Unused profiling gems, and YJIT

`test-prof` and `stackprof` are in the Gemfile and referenced nowhere: use them or drop them.
YJIT has never been tried on the suite. A cheap experiment with unknown payoff.

### VIPS-WARNING nclx noise in CI: wait for libvips 8.18

Every HEIC decode prints `heifload: ignoring nclx profile` twice, and the receipt tests decode one
every run. Nothing is wrong: libvips 8.17 and older don't read nclx (an iPhone colour profile) and
decode the image anyway; `ReceiptIntake` forces sRGB and strips metadata. libvips 8.18.0 removed
the warning, but Debian trixie and ubuntu-24.04 ship 8.15 to 8.16. Re-check when a distro we use
ships 8.18.

Silencing it with `ENV["VIPS_WARNING"]` was declined by Mick (2026-07-28): it mutes every libvips
warning to hide one. If it is ever revisited, set it **above the railtie requires** in
`config/application.rb`: `active_storage/engine` loads vips early and libvips reads the variable
once.

### README fails the `github-readme` audit

No **Installation**, **Usage** or **License** section, and no usage command in a fenced block.
Run the `writing:github-readme` skill over it as its own reviewable change.

## Outside the repo

### Manual follow-ups after the AI removal (2026-07-31)

1. **Revoke the Google API key** in Google AI Studio. Nothing reads `gemini_api_key`, but the key
   is live. Its Bitwarden copy and production-credentials entry went on 2026-09-24.
2. **Revoke the old reimbursements Airtable PAT** at airtable.com. Nothing has read it since the
   MySQL migration; it left the production credentials on 2026-09-24.
3. **Check the public Privacy Policy.** It is a CMS `Block` row, so no grep of this repo can tell
   whether it mentions sending receipts to Google. If it does, edit it in the admin CMS.
