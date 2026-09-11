# Off-topic improvements

Improvements spotted mid-task and parked as out of scope, per the "Suggest Improvements" rule.
Each is optional.

Everything below is genuinely still open, and each item says what is blocking it. What remains
needs either a production data audit, a product decision from Mick, a change to another repo, or
a live run against a third-party service.

Drained twice: 2026-07-26 (branch `off-topic-backlog`, eleven items) and 2026-09-06 (branch
`off-topic-drain`, ten items plus the membership-cards deletion). The second pass also **audited
every remaining entry against the code** and removed six that had since been resolved elsewhere
(the dev-hooks devcontainer template, multiple financial years, the MySQL 8.0/8.4 mismatch, the
Govee CSV import and its superseded twin, and richer Event schema), dropped the masthead-PNG note
as a finding rather than a task, and narrowed three that had half shipped — the cost-centre
selection, the climate mailbox ingest, and cancelled/sold-out performances.

**Settled, so don't re-raise:** a `Season` stays a schema.org `TheaterEvent` (Mick, 2026-09-06 —
see the comment in `app/models/season.rb`).

## database_consistency — schema-migration backlog (gate still advisory)

`database_consistency` is the one dev-env gate not yet driven to zero, so it stays advisory
(`|| true` in `hk.pkl` / `ci.yml`). The model-level findings are already fixed (144 `length`
validations) and the legacy integer-PK checkers are scoped out in `.database_consistency.yml`;
what remains (~170 findings) is a real **schema-migration project**:

- `ColumnPresenceChecker` (101 → add NOT NULL), `ForeignKeyChecker` (22 → add FKs),
  `MissingUniqueIndexChecker` (21), `ThreeStateBooleanChecker` (15 → NOT NULL boolean + default),
  plus the remaining index checkers.
- These need **data-aware backfill migrations on the legacy production DB** (columns may contain
  nulls / duplicates), which `strong_migrations` correctly blocks as unsafe and which need a
  production data audit. Do them as guarded multi-step migrations (backfill → add constraint) once
  the data is verified, then drop the `|| true` to make the gate enforce. Note the legacy
  integer-PK FK columns can't take a `t.references ... type: :integer` FK trivially.

**Coverage of the two encrypted models was restored on 2026-07-25** (review finding S5): Rails'
auto-injected `validate_column_size` validator registered itself lazily from `load_schema!`,
mid-iteration over the validators hash, so `database_consistency` **crashed** on
`Reimbursements::PaymentDetails` and `Reimbursements::Expense` (`can't add a new key into hash
during iteration`) and wrote a 51 KB error report instead of checking them. The step is advisory,
so CI stayed green while those two models were silently unchecked. Turning
`config.active_record.encryption.validate_column_size` off fixed it, and the ~16 findings that
reappeared for those models (mostly `LengthConstraintChecker` and `UniqueIndexChecker`) belong to
the same backlog above — including `PaymentDetails#notes`, deliberately left uncapped because it
is an append-only audit trail and a cap would eventually make a payee's bank details un-editable
(its headroom is measured in `test/models/reimbursements/encryption_test.rb`). A bounded audit log
that trims its oldest lines would be the proper fix if that ever needs closing.

## Per-worktree / per-subagent database isolation — SEEDING still manual (2026-07-26)

The mechanism now exists: `.worktree-isolate.conf` is committed, so `worktree-setup` allocates
each worktree its own `PORT`, `VITE_RUBY_PORT` and `WORKTREE_DB_SUFFIX`, and `config/database.yml`
interpolates that suffix into the **dev** databases as well as the test one (it only did test
before, which is why every worktree shared one dev DB).

**What is still open — seeding:** a freshly provisioned worktree's databases do not exist until
someone runs `bin/rails db:prepare && bin/rails db:test:prepare` in it, and `db:prepare` gives an
EMPTY dev database rather than a copy of the data in the main checkout's dev DB. The nice version
clones the main dev DB (mysqldump | mysql) so a new worktree comes up with data, and does it
automatically as part of provisioning. Until then, a new worktree needs those two commands by hand
and has no dev data.

Also still worth doing: teach the parallel-subagent dispatch path to give each agent its own
suffix, which is what would actually retire the "serialise agent test runs" rule in the
`hk-stash-vs-background-agents` global memory note — the test-DB half of that constraint is
solved per *worktree* now, but two agents inside one worktree still share it. Update the
`parallel-worktree-dev-server-ports` memory note when that lands.

## No export on My Budgets (the owner-facing budget page)

Track H added a "Download CSV" to every finance list (Expenses, Actuals, Budgets, People,
Batches, Review) and a combined workbook, but `MyBudgetsController#index` — the
owner-facing page, gated by base portal access rather than the finance permission — has
none. `Exports::Budgets` would work as-is for the owned subset, but the columns would need
a second look first: an owner arguably shouldn't see another line's full rollups, and the
exporter currently assumes the finance-wide view.

## The `reconciliation_status` index on eusa_actuals is never used by SQL

`index_reimbursements_eusa_actuals_on_reconciliation_status` (added with the offsetting-pair
work) has no SQL predicate behind it: every offset filter runs in Ruby over the store's
memoized full list (`ActualsController#index`, `Budget`'s rollups, `unbudgeted_actuals`), so
nothing ever plans against it. Left in place deliberately during the 2026-07-25 review fixes:
dropping it needs a migration on the legacy production DB, which that brief said to pause on,
and the cost is negligible at this table's size (about 300 rows per financial year).

**Fix (pick one when FY scoping lands):** either drop the index, or keep it and add the
query-level scopes the deferred financial-year rollups will want anyway
(`EusaActual.offset` / `.not_offset` used from SQL rather than filtering arrays in Ruby).
The same review deferred FY scoping for the rollups (finding 9), so the two belong together.

## Should an unlinked EUSA credit auto-attach to an *expense* budget? (product decision)

`Reconciliation.match_credit_to_budget` (called from `ReconcileController`) only ever offers
a credit row to **income** budgets: `income_budgets = budgets.select(&:income?)`. So a
supplier refund credited back on an expense nominal code has no path to the budget it
belongs to. Reconciliation leaves it unmatched, and it now shows up in the budget overview's
"actuals not attributed to any budget" card, where finance can see it but can't attach it.

`Budget#eusa_actual_amount` **does** net a credit that is already linked to one of the
budget's expenses (fixed in the 2026-07-25 round: a £300 refund on a £900 line now reads
£600), so the arithmetic is ready. What's missing is the *matching* half, and that's a
product call rather than a bug:

- Auto-attaching a credit to an expense budget by nominal code would be a guess whenever
  several budgets share a code (which is common here), and a wrong guess silently
  understates one line and overstates another.
- The safer shape is probably an explicit operator action ("credit this refund to budget X")
  on the actuals/reconcile screen, or letting a credit be linked to a specific *expense*
  (which is what the netting already keys off), rather than a code-based auto-match.
- Either way it needs a decision on year-end accrual reversals, which arrive as credits on
  expense codes too and are usually better handled as offsetting pairs.

Deliberately not implemented in the round that fixed the netting: changing matching
semantics needs Mick's call on which of those shapes finance actually wants.

## The notifier still picks a cost centre by "first row by id"

*Reconcile's half of this landed; the notifier's has not (re-audited 2026-09-06).*

`ReconcileController` now has an explicit cost-centre selector: `Reimbursements::ActualsAttribution`
attributes each pasted row to a chosen centre and carries the choice through the stateless
preview/apply round trip, with a `blank_cost_centre_id` for rows naming none. The hardcoded `"F40"`
literals went in 2026-07-26.

**What is still open:** every other caller resolves the centre as `CostCentre.default`, which is
`order(:id).first` — so once a second cost centre exists they silently pick whichever has the lower
id. That is a worse failure than a hardcode in one respect: it looks configured.

- `BaseController#notifier` (`app/controllers/admin/reimbursements/base_controller.rb:53`) — hands
  `.default` to the `Notifier`, so operator alerts name the wrong centre.
- `BatchesController` (the send mailbox and `@cost_centre`), `MailboxClient`'s default
  `receive_mailbox`, `ReimbursementsHelper`'s contact email, `BudgetsController`.

**Fix:** resolve the centre from the expense/batch being acted on rather than from `.default`.
Note `NightlyBatchJob` already does the right thing — `claims_by_cost_centre_id` falls back to the
default deliberately, so a claim whose budget names no centre reaches somebody rather than nobody.

## A long worktree name overflows MySQL's identifier limit

`.worktree-isolate.conf` derives `WORKTREE_DB_SUFFIX` from the worktree directory name, and
`config/database.yml` appends it to `bedlam_blacklightning_development` (33 chars) plus a
`_queue`/`_cache` namespace suffix (6). MySQL caps identifiers at 64 characters, so any
worktree name over ~25 characters makes `bin/rails db:prepare` abort with "Identifier name
'…' is too long" — the worktree provisions fine and only fails when you first touch the
database. A `.worktrees/reimbursements-first-name-greeting` hit this; the workaround was
hand-editing the generated `mise.local.toml` to a shorter suffix.

**Fix:** cap the generated suffix (truncate to ~20 chars, or hash the tail) in dev-hooks'
`isolate-worktree.sh`, and/or note the limit in `.worktree-isolate.conf`'s header comment so
the constraint is visible where the naming decision is made. The upstream script is the
better home — every repo using this isolation scheme has the same ceiling.

## An intermittently flaky system test

`bin/rails test:system` fails roughly 1 run in 5 with a single error, and passes the other
four. Observed on 2026-07-27 across ~8 consecutive runs while landing the test-suite speedup
(`plans/test-suite-speedup.md`): 2 failing runs, 6 clean. It is **not** parallelisation —
system tests are pinned to `parallelize(workers: 1)` and one of the failures happened with
workers already forced to 1, so it is a timing race in a browser test.

Not attributed to a specific test: both failures were caught in runs whose output was filtered
to the summary line, and every attempt to reproduce it afterwards came back green. `main` was
only sampled once (clean), so this may well predate the speedup branch rather than come from it.

**Fix:** run `bin/rails test:system` in a loop capturing full output until it reproduces
(`for i in $(seq 20); do bin/rails test:system > /tmp/sys-$i.log 2>&1; done`, then grep the
logs for `^Error:`/`^Failure:`), name the test, and fix the race — most likely a missing
Capybara wait on an assertion that races the Turbo/Stimulus render, given the suite's use of
`assert_selector … wait: 5` in some places and bare assertions in others.

## CI setup time is apt-get update and an image pull, not packages

Measured 2026-07-27 across 6 runs. `Install packages` sits at 26-37s and `Initialize
containers` at 28-31s, and neither moved when the obvious levers were pulled: dropping
google-chrome-stable (a ~110MB download the runner already ships), git, pkg-config and the
vestigial libpq-dev left the step at 28s, and tightening the MySQL health probe from a 10s
interval to 3s left container init at exactly 28s.

So the time is `apt-get update` fetching package lists, and pulling the mysql image --
not the things being installed.

**Fix:** if setup is worth attacking, the levers are caching apt lists, dropping the service
container for the runner's preinstalled MySQL (above), and caching the 11s `bin/vite build`
on a source hash. Setup is ~83s against ~100s of tests, so it is now roughly half the job.

## VIPS-WARNING nclx noise in CI — wait for libvips 8.18

Every HEIC decode prints `heifload: ignoring nclx profile` twice, straight to fd 2 (GLib's
default handler; ruby-vips installs none of its own — its handler is commented out in the gem
over a GIL deadlock between libvips worker threads and a blocked main thread). The
reimbursements receipt tests decode the fixture on every run, so a CI log is full of it.

Nothing is wrong: nclx is a compact video-style colour profile that essentially every iPhone
HEIC carries, libvips ≤8.17 doesn't support it, and it decodes the image anyway. Our pipeline
is unaffected — `ReceiptIntake#prepare` forces `colourspace(:srgb)` and `#encode` strips
metadata, and a real decode failure raises `Vips::Error` instead (the `truncated_receipt.heic`
path). **libvips 8.18.0 (Dec 2025) removed the warning**: `heifload` now reads nclx into CICP
metadata and logs at `g_info`. Checked the source at v8.15.1/v8.16.0/v8.16.1/v8.17.0 — all
four still warn. Debian trixie and ubuntu-24.04 ship 8.15–8.16, so there is no upgrade path
short of building libvips ourselves.

**Fix:** re-check when a distro we use ships libvips ≥ 8.18. Silencing it in the meantime
(`ENV["VIPS_WARNING"] = "1"`, any value suppresses) was considered and deliberately declined
by Mick 2026-07-28 — it would mute *all* libvips advisory warnings to hide one. If it is ever
revisited, note the ordering trap: it must be set **above the railtie requires** in
`config/application.rb`, not next to `require "image_processing/vips"`, because
`active_storage/engine` eagerly requires `active_storage/analyzer/image_analyzer/vips` and
libvips reads the variable once, in `vips_init()`.

## `ImportParsing`'s categorisation helper is user-matching-specific

*Noticed 2026-07-28 while writing `Reimbursements::BudgetImport`.*

The concern's parsing half (`parse_data`/`parse_tsv`/`parse_xlsx`/`find_column`) is genuinely
generic and the budget import reuses it happily. Its categorisation half is not:
`build_categorized_result(multi_match_bucket:)` hardcodes the keys `:existing_user` /
`:existing_users`, and `determine_bucket` is expected to return a `User`. `BudgetImport`
therefore writes its own `categorize`, duplicating the bucket-loop shape.

**Fix:** rename the payload key to something domain-neutral (`:match` / `:matches`) and let
the including class name its own buckets, then have `BudgetImport` use it. Small, but it is
the difference between a shared concern and a concern with one real user and one squatter.

## Manual follow-ups after the AI removal (2026-07-31)

*Noticed while removing the Gemini extraction and the finance AI checker.* Three things the
code change can't do itself, all outside the repo:

1. **Revoke the Google API key.** Nothing reads `gemini_api_key` any more, but the key itself is
   still live. Revoke it in Google AI Studio, then delete the `gemini-api-key` secret from
   Bitwarden Secrets Manager. `fnox.toml` is gitignored, so its `REIMBURSEMENTS_GEMINI_API_KEY`
   line was removed on this machine only — anyone else with a checkout has to delete their own
   copy of that line, or `fnox exec` keeps doing a dead Bitwarden lookup and exporting the key
   into their dev shell.
2. **Drop `gemini_api_key:` from the production credentials.**
   `bin/rails credentials:edit --environment production` — the development credentials never
   held a value (they're publicly readable). Harmless if left, but it's dead secret material.
3. **Check the public Privacy Policy.** It is a CMS `Block` row, not a file, so no grep of this
   repo can tell you whether it mentions sending receipts to Google. If it does, edit it in the
   admin CMS — it would now be describing processing that no longer happens.

## README fails the `github-readme` audit

*Noticed 2026-07-31 while syncing the version table.* The `writing:github-readme` audit script
reports the README has no **Installation**, **Usage** or **License** section, and no usage
command in a fenced code block. The tech-stack table and the setup snippet pass.

**Fix:** run the `writing:github-readme` skill over it. Deliberately not done as part of a
dependency bump — restructuring the README is a separate, reviewable change.

## Heading anchors keep a slug built from the IAL text

*Noticed 2026-07-31 during the commonmarker 2.9 upgrade.* commonmarker slugifies a heading from
its **raw** source, so `## My Heading { .text-danger }` yields
`id="my-heading--text-danger-"` — the IAL leaks into the anchor even though `MdHelper` strips it
from the rendered text afterwards. Pre-existing (2.8 did the same); an explicit `{ #my-anchor }`
already overrides it, and `realign_heading_anchor` keeps the self-link consistent either way.

**Fix (if wanted):** re-slugify a heading from its cleaned text after `apply_ial`. Note this
would *change existing anchor URLs* on any page whose heading carries a class-only IAL, so it
needs a deliberate decision about breaking inbound links, not a silent tidy-up.

## The Open-Meteo forecast tail is fetched and then discarded

*Noticed 2026-08-06.* `OutdoorPollJob` requests `forecast_days=1` purely for self-heal margin, and
`ReadingIngest.upsert_series!` drops every row dated in the future so predictions are never drawn
as observations.

**Fix (if wanted):** keep those rows behind a flag and render them as a distinct dashed *forecast*
segment past "now". Genuinely useful for "should the dehumidifier run tonight" — but it must be
visually unmistakable, which is why it wasn't done as a silent extension of the existing line.

## No retention or rollup policy for `climate_readings`

*Noticed 2026-08-06.* At ten-minute polling the table grows about 52k rows per sensor per year,
which MySQL will not notice for years. There is no pruning job and, deliberately, no plan to add
one — year-on-year comparison is the point of keeping it.

**Fix (eventually):** if the table ever passes a few million rows, add a rollup table of hourly
(or daily) aggregates for long ranges rather than deleting history. `SeriesQuery`'s bucketing is
already the shape a rollup would take, so it would be a swap of the source table, not a rewrite.

## A dew-point-margin alert would be the point of all this

*Noticed 2026-08-06.* The dashboard shows the condensation-risk margin, but somebody has to look
at it. The damage from crypt damp happens over days, and nobody watches a chart for days.

**Fix:** a job that emails when a sensor's margin stays under `ClimateHelper::CONDENSATION_RISK_MARGIN`
for N consecutive hours. Deliberately out of scope for the first cut (Mick asked for the charts),
but this dashboard is really a prerequisite for it — the readings and the margin already exist.

## Vendor-file parsers are a separate family from the sheet importers

*Noticed 2026-08-06 while adding the climate CSV import.* The app now has two distinct kinds of
import and it is worth naming the split before someone "unifies" them:

- **Sheet importers** (budget, membership, user, show-crew) share `ImportParsing` (paste-TSV +
  roo-xlsx, fuzzy header matching) and a preview→apply wizard, because a human makes per-row
  decisions.
- **Vendor-file parsers**, i.e. `Reimbursements::Reconciliation.parse_actuals_rows` (EUSA's Sage
  export) and `Climate::CsvImport` (Govee's). These parse a fixed third-party format with stdlib
  CSV, own their delimiter sniffing and quirks, and have no per-row decisions to make.

Both vendor parsers hand-roll their CSV reading, which looks like duplication but mostly is not:
each one exists to cope with a different vendor's specific mess (Govee's BOM and prose header;
Sage's British dates and debit/credit columns).

**Fix (if it ever earns it):** a small shared `DelimitedFile` helper for the genuinely common
parts (BOM strip, delimiter sniff, header-index lookup), leaving the vendor quirks in each parser.
Not worth doing for two callers; worth doing at three.

## The climate mailbox ingest is unverified end to end

*Noticed 2026-08-06; the sensor-matching half was answered since (re-audited 2026-09-06).*

`Climate::MailboxPollJob` is unit-tested against a fake mailbox but has never run against real
Graph: it needs a mailbox, an `ApplicationAccessPolicy` covering it, and Govee's scheduled export
pointed at it.

The open question about Govee's email **has been settled**: the export identifies no device, not in
the subject and not in the filename, which is why `#sensor_for` resolves the sole Govee sensor and
otherwise leaves the message unread and fires a deduped `ConfigurationError` rather than guessing.
So the remaining work is the live run, plus the multi-sensor case: with more than one Govee sensor
nothing can be attributed, and the extension point is a mailbox (or plus-address) per sensor
resolved on the recipient, not a cleverer heuristic.

## The pretix modal dialog is driven by two controllers at once

*Noticed 2026-08-17.* `shared/_pretix_modal.html.erb`'s `<dialog>` declares
`data-controller="modal"` (for `close` / `backdropClose`) while carrying
`data-pretix-modal-target="…"` attributes belonging to the `pretix-modal` controller on an
ancestor. It works, and the split is defensible — the generic dialog behaviour genuinely is
generic — but reading the partial gives no hint that `showModal()` is called from a *different*
controller than the one named on the element.

**Fix (if it earns it):** either fold open/close into `pretix-modal`, or use a Stimulus outlet
so the relationship is declared rather than implied. Not urgent; the backdrop-close path is
covered by the modal system test.

## The Active Storage representations override drops upstream's strict-loading blob scope

*Noticed 2026-08-24.* `ActiveStorage::Representations::RedirectController` (our override)
subclasses `ActiveStorage::BaseController` and includes `ActiveStorage::SetBlob` directly,
rather than subclassing upstream's `ActiveStorage::Representations::BaseController`. That
skips upstream's `blob_scope` override, which is `ActiveStorage::Blob.scope_for_strict_loading`
— a guard against a lazily-loaded association firing inside a hot image route.

It also skipped upstream's `InvalidSignature` rescue, which is what turned a forged variation
key into a 500 (fixed 2026-08-24); the strict-loading scope is the other half of the same
divergence and is still missing.

**Fix (if it earns it):** subclass `ActiveStorage::Representations::BaseController` and move
the Vips/LoadError handling to a `rescue_from`, since upstream does the processing in a
`before_action` where a method-level `rescue` cannot reach it. The Honeybadger context call
then needs re-ordering too — it has to run *before* `set_representation`, which is where the
image backend actually runs. Low value on its own; worth doing next time this file is opened.

## `sortable_controller`'s reindex counts rows that are on their way out

*Noticed 2026-08-24; team members resolved 2026-09-05.* `#updateOrder`
(`app/javascript/controllers/sortable_controller.js`) renumbers every `[data-sortable-item]` in
the container from 0, including rows the user has already removed, and a row added with "Add"
gets no number until something is dragged. **Team members no longer use it**: `TeamMemberOrdering`
stamps `display_order` from the row's position in the submitted params on save (browsers post a
form in document order), so the team member row carries no hidden order field and the controller
finds nothing to renumber there.

`OpportunityRole#ordering` still goes through the hidden field and has both gaps. The same
server-side pattern would close them: an `opportunity_roles_attributes=` override stamping
`ordering` by row position, then drop the hidden field and the JS renumbering altogether.

## SEO follow-ups left open after the 2026-08-30 audit

The audit's code-side findings landed on `seo-fixes`. These four need something this repo cannot
supply.

### No phone number exists to publish

The footer now carries the postal address as crawlable text on every page, which fixes two thirds
of the Name/Address/Phone signal local search ranks on. There is **no phone number recorded
anywhere in the app** to add as the third, and inventing one is not an option. If the box office
has a public number, add it to the footer `<address>` and to `SchemaHelper::VENUE_ADDRESS`'s
parent node as `telephone`.

### Search Console and analytics are unverified

No `google-site-verification` meta tag, no analytics tag of any kind, and no Google TXT record in
DNS (only `MS=ms94671060`). Verification may exist via an uploaded HTML file — worth confirming.
Until it does, none of the work above can be measured: there is no before-and-after to read.

## The API does not expose performances or ticket prices

`Event#as_json` lists `venue`, `pictures` and `team_members` but not `event_occurrences` or
`ticket_prices`, so `/api/v1` consumers still see only the free-text `price` and the run dates.
Adding them is a deliberate decision rather than an oversight — per CLAUDE.md, anything added to
`ransackable_attributes` is also exposed through the API, and `test/.../leakage_test.rb` enforces
that — so decide what the API should say before widening it.

## `Venue` has no capacity column

*What is left of "a cancelled or sold-out performance has nowhere to be recorded" — the rest
shipped with the pretix performance sync (re-audited 2026-09-06).*

`EventOccurrence` now carries `cancelled` and `sold_out`, both rendered as badges on the
performance row and mapped to schema.org `EventCancelled` / `SoldOut` by
`SchemaHelper#performance_status` / `#performance_availability`, so pulling one night no longer
means deleting the row.

Still missing: `Venue` has no capacity column, so nothing can emit `maximumAttendeeCapacity`.

## `display_price` reads oddly when one band is free and the others are not

The compact board form joins the amounts — "£10/8/7" — and the "Free" shortcut only fires when
*every* band is zero, so a show with a paid standard band and a free members band prints "£10/0".
Not wrong (it means £10/£0) but it reads badly across a room. Left alone rather than special-cased:
the mixed case is rare, and the obvious fixes ("£10/free", dropping the zero) each either break the
compact convention or hide a band. Revisit if a real show ever prices this way.

## The committee resources page has no link anywhere

`admin/static#committee` is routed and now permission-gated, but nothing in the admin sidebar or
dashboard links to it — the only way in is typing the URL. Either add a sidebar entry gated on
`can?(:access, :committee)` or confirm the page is dead and remove it.

## A rejected report attachment fails silently, after 30 minutes of pointless retries

Issue #169 (Dec 2022) was MailerSend's SMTP relay answering `450 This file type is not supported`
to `ReportsMailer#send_report`'s `report.xlsx`. MailerSend sends that as a 4xx, so
`ApplicationJob`'s `retry_on Net::SMTPServerBusy` (added 2026-01-24 for the genuine 450 rate
limits) now retries a permanent rejection ten times over ~30 minutes before giving up, and the
requester, who was told "will be emailed to you when it is ready", never hears anything either
way. `.xlsx` is on MailerSend's supported list today (Sep 2026), so the rejection should not recur,
but the shape of the failure is the same for any future 450 that is not a rate limit: consider
matching the message (`file type`, `from.email must be verified`, `recipient is suppressed`) to
`discard_on` instead of retrying, and telling the requester when a report cannot be delivered.

## The BACS spreadsheet's amount column loses its currency format (verified 2026-09-06)

`BacsXlsx#write_row` writes the amount with `sheet.add_cell(row_index, COL_AMOUNT, row.amount.to_f)`,
and the comment beside it claims "the template's currency format renders it". It does not.
rubyXL's `add_cell` **replaces** the cell, dropping the style the template pre-styled that row
with, so the written cell carries `General`.

Verified by generating a real one-row workbook through the service and reading it back:

| cell | number format |
|---|---|
| template row 3 (blank, pre-styled) | `_-"£"* #,##0.00_-;\-"£"* #,##0.00_-;_-"£"* "-"??_-;_-@` |
| written row 3 | `General` |

So every BACS spreadsheet EUSA has received shows `1234.56` where the template intended
`£1,234.56`. Cosmetic only — the value is a true number, so the GRAND TOTAL `SUM` is unaffected,
and the total row keeps its own format because nothing writes to it.

Fix: use `sheet[row][col].change_contents(value)` (keeps the existing style) instead of
`add_cell`, or re-apply the format after writing. `change_contents` was confirmed to preserve
`"£"#,##0.00` on the international template in the same session. The text cells are unaffected —
`text_cell` sets `@` explicitly straight after `add_cell`.

Blocking: nothing, beyond wanting a regression test that asserts the written amount cell's
number format is the template's and not `General`.

## A Tom Select `<select>` carrying layout classes draws a box inside a box (noticed 2026-09-10)

CLAUDE.md's "Admin forms" section states the rule: a select Tom Select will take over must carry
only `simple-select2`, because Tom Select copies the `<select>`'s classes onto its `.ts-wrapper`,
which already draws the box. `app/views/admin/debt_checkers/_user_lookup.html.erb:17` breaks it —
`class: "simple-select2 w-full"`. Worth a sweep for other hand-written `simple-select2` classes
carrying width/border utilities (simple_form's `CollectionSelectInput` strips them for you, so only
the hand-rolled `select_tag` / `input_html:` cases can be wrong).

Blocking: nothing — needs a browser look to confirm the doubled box actually renders on that page
before changing it.

## The shared user picker is gated on an Event-specific permission (noticed 2026-09-10)

`app/views/shared/form/_user_field.erb:1` defaults `all_users:` to `can?(:add_non_members, Event)`,
whose grid description is "Add non-members to events, mainly for archiving purposes"
(`app/controllers/admin/permissions_controller.rb:92`). That partial is rendered from five
unrelated forms — team-member credits, maintenance credits, staffing jobs, marketing-creatives
profiles, shared debt — so whether a non-member is pickable on a *staffing* form is decided by an
*event-archiving* permission. Either the permission should be renamed to what it actually governs,
or each caller should pass the `all_users:` its own screen needs (`_debt_form.erb` already passes
`all_users: true` for exactly this reason).

Blocking: it is a permissions change, so it needs Mick's call on which of the two readings is right.
---

## Cost-centre scoping pass (2026-09-10) — noticed, out of scope

### `Reimbursements::BudgetImport` matched budget names across cost centres

`BudgetImportsController#build_import` passes `store.budgets_for_year` as `existing_budgets`, and
`BudgetImport` indexes it by name only — despite the documented contract being "matched by name
within one `(financial year, cost centre)`". With two centres both running a budget called "Props",
a Fringe import would have matched termtime's line and logged a revision against it.

Fixed *incidentally* by this branch, because `budgets_for_year` is now cost-centre scoped and the
wizard's `?cost_centre_id=` feeds the store's scope. It is worth a test of its own naming that
rule, rather than resting on a scoping side effect: if `budgets_for_year` were ever unscoped again,
this silently regresses to matching across pots.

### `expense_edits/edit.html.erb` trips `erb-no-duplicate-branch-elements`

Two herb-lint hints (non-gating, autocorrectable with `herb lint --fix`): the
`<div class="grid gap-4 sm:grid-cols-2">` wrapper is repeated in both branches of the UK/
international rail conditional. Lifting it outside the conditional is the suggested fix; check
that it does not change which fields the rail-toggling Stimulus controller can see, since that
form's `data-rail-required` handling reads the surrounding structure.

### `NightlyBatchJob` and the store disagree about unplaced claims, deliberately

`claims_by_cost_centre_id` files a claim with no cost centre under `CostCentre.default`;
`DatabaseStore#in_cost_centre` shows it under every centre. Both are right for their job (a
reminder needs one recipient list, a filter does not), and both are commented — but it is two rules
for one question. If cost centres ever become mandatory on a budget, collapse them into one.

### Batches still have no `cost_centre_id` column

`reimbursements_batches` has none while `reimbursements_batch_attempts` has one NOT NULL. Every
reader here derives the batch's centre from the expenses it holds, which is exact now that Build
Batch builds for one centre only — but it is a derivation that goes stale the instant a reopen
unlinks the expenses (which is why the reopen path resolves the mailbox before reverting) and
returns nothing for a batch whose expenses were deleted. A `cost_centre_id` column, nullable then
backfilled from the expenses then made NOT NULL, would make it a fact. Not done here because it
needs the user's sign-off on the migration and the derivation is correct today.

### Reconcile, Expenses and Budget updates are not cost-centre scoped

Reconcile is per-ROW by design and must stay so. The finance Expenses list (`ExpenseEditsController
#index`) and Budget updates render no selector, so a `?cost_centre=` in their URL scopes
`budgets_for_year` but not their own lists — harmless, but inconsistent. Worth deciding whether
they get the selector too.

### Every import wizard needs a Turbo-Frame escape rule, not per-link vigilance

Fixed here: all five links out of the budget-import wizard rendered "Content missing" when
clicked, because a link inside a Turbo Frame navigates the frame and none of those destinations
carries one. `shared/back_link` now takes `turbo_frame:` and each link passes `_top`, with a
system test per wizard — but nothing *stops* the next link being added without it. A lint rule
(herb, or a system test that walks every link inside a `turbo_frame_tag` in these views) would.
Reconcile is currently clean only because both its links point back at itself.

### An imported expense keeps `submitted_at` = now unless the sheet dates it

`Expense`'s `before_create` stamps `submitted_at ||= Time.current`, so a 2019 claim imported with
no "Date submitted" column reads as submitted today. Harmless for the terminal statuses (nothing
reminds about them) and the column exists for anyone who has the real dates, but a historical
import that skips it leaves the expenses list sorted as if the whole ledger arrived at once.

### The expense import writes UK BACS claims only

`Reimbursements::ExpenseImport` has no `payment_method` column, so every imported claim is
`uk_bacs`. A historical *international* claim imports fine (its IBAN/BIC are only read on the
money path, which a settled claim never re-enters), but it is recorded on the wrong rail. Adding
the column means adding IBAN/BIC/foreign-amount/currency columns with it — four more headings for
a case that is one claim at a time, so the normal form is the better route today.

### `:canonical_tsv` is a marker `ImportParsing#parse_data` doesn't know

Both wizards now pass `input_type: :canonical_tsv` and each translates it to `:paste` itself
(`@rows = parse_data(data, @escaped ? :paste : input_type)`) before the concern sees it, because
`parse_data`'s `case` has only `:paste` and `:xlsx` and its `else` records "Unknown input type" and
returns **zero rows** — an import that silently previews nothing rather than erroring. The concern
owns the escaping half of this contract, so it should own the input type too: `when :paste,
:canonical_tsv then parse_tsv(data)`, and the `@escaped` assignment would be the includer's only
line. A third wizard that forgets the translation gets the empty preview with nothing on screen to
explain it.

### `escape_cell` is applied to every cell, `unescape_cell` only to `TEXT_FIELDS`

Both wizards' `tsv_row` escapes all columns on the way out, but the way back only unescapes the
handful listed in `TEXT_FIELDS` — so a backslash in any other column survives the preview
DOUBLED (`4\000` becomes `4\\000`). Harmless today: every other column is a parsed amount, date,
enum or email by then, and a committee typing a backslash into a nominal code or a budget type
already gets a row error naming it. But the asymmetry is not stated anywhere and the safe reading
is either to escape only the fields that are unescaped, or to unescape everything.

### `ImportParsing#find_column`'s substring fallback is a loaded gun for any wide sheet

It matches any header *containing* a keyword, so on a sheet whose fields are near-anagrams
("Reference"/"Payment reference", "number"/"Account number") it silently reads the wrong column.
`ExpenseImport` stopped using it — exact names first, multi-word substrings only, ambiguity
refused, and the mapping shown in the preview. `BudgetImport` and the membership import still use
it. Neither is known to be wrong today (their sheets are narrow), but `BudgetImport`'s
`COLUMNS[:name]` ends in a bare `%w[budget]` and its `:amount` in a bare `%w[total]`, which is the
same shape. Worth porting `ExpenseImport`'s matcher into the concern and moving all three onto it.

### The `import_key` comparison folds case but not accents

`ExpenseImport.key_match` downcases, matching the common `OLD-1`/`old-1` case; the column's
`utf8mb4_unicode_ci` collation also folds accents, so a sheet mixing `réf-1` and `ref-1` still
dead-ends at the unique index. Deliberate: over-matching here would bucket a genuinely new claim
as already imported and drop it silently, which is far worse than a blocked import. The apply
rescue now names renaming the reference as the fix, so it is recoverable. The exact answer is to
ask MySQL (`Expense.where(import_key: refs)`) rather than compare in Ruby, which means giving the
model a DB-backed lookup instead of the `existing_expenses:` collection it takes today.

### `ExpenseForm#settled` is an invariant stated in prose, not enforced

It is safe because nothing returns an unbatched claim to Approved — `revert_expense_to_approved!`
is only reached for a claim with a batch, and the finance edit form writes a fixed attribute hash
with no `status` key. The day someone adds a "put this claim back in the queue" button that writes
`status: Approved` through `store.update_expense!`, a settled Invoice imported without a payee
trio becomes a payment to the producer instead of the supplier.

NOT done here, on purpose. The obvious guard — a model validation refusing an Invoice at Approved
with a blank trio — would also fire on `revert_expense_to_approved!` for any legacy batched Invoice
that predates `invoice_without_payee?`, breaking batch reopen on a money path, and there is no way
to check that from a dev machine. `ReviewSupport`/`approve_blocker` is the wrong home too: it
returns `:skipped_wrong_status` for anything not Pending, so a re-queue button would never reach
it. Before adding the validation, run in production:

    Reimbursements::Expense.where(expense_type: Reimbursements::Expense::TYPE_INVOICE,
                                  status: %w[Approved Submitted Paid])
                           .count { |e| e.payee_name_override.blank? }

If that is 0, scope the validation to `status_changed? && approved?` and ship it.

### Review and the finance expense-edit form still check budget EXISTENCE only

`budget_record_id_error` (FinanceController) answers "does this row exist", which is the right
rule for the expense-edit form — it deliberately offers the inactive budget a claim is already
on — but Review's picker is `active_budgets`, so a budget deactivated while the queue is open is
still accepted there. Neither rescues `DatabaseStore::BudgetGoneError`, so a delete landing inside
their race window is still a 500. Unchanged from before this fix, and both are finance's own
screens (an operator retypes; no producer loses a claim), which is why it was left. Review wants
`@form`-style offerable ids or an explicit `active` check; both want the rescue.

### `owner_ids_error` has the same shape and the same race

A Person deleted between a budget form being drawn and saved gets the same pre-flight check and
the same unnamed foreign-key 500 behind it. `BudgetGoneError`'s sibling (`PersonGoneError`, or a
shared `LinkGoneError`) would let the budget forms re-render instead. Not hit in production yet.

### Radio buttons render as squares, so a radio pair reads as two checkboxes

`simple_form`'s `:vertical_collection` wrapper (and the admin `tailwind_horizontal_collection`
beside it) applies `FormStyles::CHECKBOX` to `radio_buttons` as well as `check_boxes`, and that
constant carries Tailwind's `rounded` — which overrides the native circle. So the area form's
"Total expenses / Total net" pair (and `application/_answer_fields`' Yes/No) renders as a filled
SQUARE next to real checkboxes on the same form, and nothing on screen says the two options are
mutually exclusive. The fix is a `FormStyles::RADIO` (`rounded-full`) plus a collection wrapper
mapped for `radio_buttons` only; left alone here because it restyles every existing radio in the
app, which is a wider change than the area basis it was noticed on.

### `Reimbursements::Area#income?` has no callers

`budgets.any?(&:income?)`, added with the model and never read — the Phase 2a suppression it
would have suited went through `AreaRollup#mixed_budget_types?` instead, and Task 5 replaced
that with the declared basis. `debride` does not flag it (an AR model's public reader), so it
will sit there until someone deletes it.
