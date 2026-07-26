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

