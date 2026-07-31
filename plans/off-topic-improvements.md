# Off-topic improvements

Improvements spotted mid-task and parked as out of scope, per the "Suggest Improvements" rule.
Each is optional.

Everything below is genuinely still open, and each item says what is blocking it. The file was
drained on 2026-07-26 (branch `off-topic-backlog`): eleven items landed as their own commits, and
what remains needs either a production data audit, a product decision from Mick, or a change to
another repo.

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

## Upstream a mise-driven devcontainer template into dev-hooks

- Consider upstreaming devcontainer-mise support into the `dev-hooks:dev-env-setup` skill: it
  already standardises mise + hk + CI, but doesn't yet template a mise-driven `.devcontainer/`.
  (This is a change to the dev-hooks plugin marketplace, not to this repo — which is why the
  2026-07-26 drain left it here: nothing to change in BlackLightning.) Worth carrying up with it:
  the apt list this repo settled on for a precompiled-Ruby devcontainer, and the
  `.worktree-isolate.conf` + `database.yml` suffix recipe now wired up here.

## Admin::MembershipCardsController is unrouted dead code — NEEDS MICK'S GO-AHEAD TO DELETE

`admin/membership_cards` has **no routes** — the `resources :membership_cards` line in
`config/routes.rb` is commented out (~line 334) and `bin/rails routes -c admin/membership_cards`
returns nothing. The controller (whose own header says "Has been severely neglected. Can probably
use the GenericController.") and its views (`index`/`show`/`_index_results`) are therefore
unreachable. Its `index` still renders the unguarded `shared/pages/index` turbo_stream fragment, but
that's moot while unrouted.

Scoped out fully on 2026-07-26 while draining this file. **Removal is the right call** and the
cluster is bigger than the note said — every one of these is reachable only through the unrouted
controller:

- `app/controllers/admin/membership_cards_controller.rb`
- `app/views/admin/membership_cards/` (`index`, `show`, `_index_results`)
- `test/functional/admin/membership_cards_controller_test.rb` (an empty class, no tests)
- `lib/membership_card_pdf.rb` — already gutted to a no-op stub ("Prawn broke on upgrading to
  Ruby 3.1. Most of the contents of this file got deleted."), so `generate_card` produces nothing
- `app/javascript/controllers/print_controller.js` — used by exactly one template, the unreachable
  `show`, which POSTs to a hardcoded box-office receipt printer at `192.168.1.254:8179` /
  `localhost:5000` behind an `if request.remote_ip == "79.77.20.249"` check
- the commented-out `resources :membership_cards` block in `config/routes.rb`

The `MembershipCard` **model stays** — `User has_one :membership_card`, `delegate :card_number`,
the merge path and `MembershipMailer` all use it.

Not done because deleting files is exactly the case the worktree workflow says to surface rather
than merge silently (and the sandbox declined the deletion). Say the word and it is one commit.

---

## Multiple financial years — PLANNED (post-MySQL)
Now designed: a year-selector model (one active year + look-back), landing at the MySQL
cutover, not on Airtable. Full plan in `docs/reimbursements/mysql-migration-and-roadmap.md`
(financial_year FK on budgets/expenses/actuals, EUSA codes stay on CostCentre with a thin
per-year join only if they ever rotate, clone-into-next-year). Interim on Airtable: one base
per year, swap the base id if a new Fringe starts before the cutover. — Mick, 2026-07-12

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


## Reconcile and the notifier still pick a cost centre by "first row by id"

The hardcoded `"F40"` literals are gone (2026-07-26): `Reconciliation.parse_actuals_rows`
requires `cost_centre_code:` with no default, and `ReconcileController` raises
`CostCentre::NotConfiguredError` rather than guessing. But the *selection* is still
`CostCentre.default`, which is `order(:id).first` — so once a second cost centre exists,
reconcile silently filters a pasted export by whichever cost centre happens to have the lower
id, and `BaseController` hands the same `.default` to the `Notifier`.

That is a worse failure than the old hardcode in one respect: it looks configured. A termtime
export pasted into reconcile would have its rows dropped as "another cost centre's" with no
indication why, or termtime rows would be filed under the Fringe.

**Fix:** give the reconcile wizard an explicit cost-centre selector (and carry the choice
through the stateless preview/apply round trip, which re-parses the pasted text), and resolve
the notifier's cost centre from the expense/batch being acted on rather than from `.default`.
Until then the portal is single-cost-centre in practice, whatever the copy says.


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


## CI tests against MySQL 8.4, production runs 8.0

`.github/workflows/ci.yml` pins the service container to `mysql:8.4`, but
`config/deploy.yml`'s accessory is `mysql:8.0`. The devcontainer's `mysql:8` floats to
whatever the latest 8.x is (currently 8.4.8 locally), so **no environment actually tests
against the version production runs**, and CI tests against a newer one. 8.4 changed
defaults and dropped deprecated behaviour relative to 8.0, so this is the wrong direction
for a safety net to lean.

**Fix:** align CI (and ideally the devcontainer) to `mysql:8.0`, or upgrade production to
8.4 deliberately. Note the ubuntu-24.04 runner ships MySQL **8.0.46** preinstalled
(disabled; root/root, `sudo systemctl start mysql.service`), so switching CI to it would fix
the mismatch *and* remove the ~28s spent pulling the service-container image. The cost is
reproducibility: the runner's version drifts with the image, where the service container is
pinned by SHA digest (deliberately, per c9933f12).

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

## The VAT soft block is the only one with no live reveal

*Noticed 2026-07-31 in review of the AI removal.* `ExpenseForm` has two soft blocks. The
large-amount one reveals itself as you type (`reimbursements_receipt_controller.js#checkAmount`
on `input`), but the VAT one is now server-rendered only, so a producer who enters
`12.50 / 12.50` first learns about it from a failed submit.

Not a regression — the live toggle only ever fired from the extractor's `#fill`, so it never
worked for a hand-typed claim. But with extraction gone, server-render is the *only* path, and
the two soft blocks now behave inconsistently for no reason a user could infer.

**Fix:** a `checkVat()` on the controller bound to `input->` on both amount fields, mirroring
`checkAmount`. Three lines plus a target. Deliberately not done as part of the removal — it is
new behaviour, not cleanup.
