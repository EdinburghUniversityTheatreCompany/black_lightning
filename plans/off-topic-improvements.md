# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

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
  (This is a change to the dev-hooks plugin marketplace, not to this repo.)

## Prune ruby-build-only apt packages from the devcontainer (needs a bundle-install test)

Now that Ruby is installed precompiled (`compile = false`, jdx/ruby), the packages in
`.devcontainer/Dockerfile.dev` that existed *only* to build CRuby from source via ruby-build —
`autoconf`, `libreadline-dev`, `libgdbm-dev`, `libncurses-dev`, `libgmp-dev`, `uuid-dev` — are
no longer needed for Ruby itself. They appear unused by the app's compiling native gems
(bcrypt, bcrypt_pbkdf, mysql2, nio4r, puma, json, prism, racc), so they're *probably* removable.
Keep `build-essential`, `libssl-dev`, `zlib1g-dev`, `libyaml-dev`, `libffi-dev`,
`libmariadb-dev-compat`, `pkg-config` (native gem builds). Before removing anything, verify with a
real `bundle install` in a trixie container using the pruned set — don't remove on inspection alone.
Payoff is modest (small image/layer shrink); the Ruby-compile time saving is already captured.

## Admin::MembershipCardsController is unrouted dead code

`admin/membership_cards` has **no routes** — the `resources :membership_cards` line in
`config/routes.rb` is commented out (~line 233) and `bin/rails routes -c admin/membership_cards`
returns nothing. The controller (whose own header says "Has been severely neglected. Can probably
use the GenericController.") and its views (`index`/`show`/`_index_results`) are therefore
unreachable. Its `index` still renders the unguarded `shared/pages/index` turbo_stream fragment, but
that's moot while unrouted. Decide to either **remove** the controller + views + empty test, or
**wire it up** (route it and convert to `GenericController`, which already guards the index
turbo_stream via `render_index_stream_or_full`). Left untouched for now since it can't be triggered.

## Opportunity show contact line drops the viewer context

`app/views/admin/opportunities/show.html.erb`'s contact field calls
`@opportunity.submitter_display_name` **without** passing `@current_user`, unlike the other
call sites (`OpportunityCardComponent`, the created_by field before it was restructured), so
`User#name(current_user = nil)` renders the creator's name without viewer-aware formatting.
Probably harmless (admins see full names anyway), but inconsistent — pass `@current_user` or
document why it's omitted. Also, `Opportunity#css_class` calls `.html_safe` on the literal
strings `"table-success"`/`"table-danger"` for no reason; plain strings would do.

## CarouselItem#tagline: authored as Markdown but rendered as plain text (inconsistent)

`CarouselItem#tagline` is edited through the `Admin::MdEditorComponent` Markdown editor
(`app/views/admin/carousel_items/_form.html.erb:6`) but is output raw, NOT through
`render_markdown`, in `app/components/public/basic_info_component.html.erb:11`. So a tagline like
`**bold**` or `##Heading` shows up literally on the public carousel rather than as formatted HTML —
the opposite of every other Markdown column in the app. Because of this mismatch it was
deliberately **excluded** from the `markdown:fix_heading_spaces` cleanup task
(`lib/tasks/logic/markdown_heading_fix.rb` `TARGETS`): inserting a space there would visibly change
the literal string users see rather than fix a heading.

Pick one and make it consistent:
- **Render it as Markdown** — swap the raw output for `render_markdown(@tagline)` (or
  `render_plain`/`truncate_markdown` if only inline emphasis is wanted, no block elements). Then
  add `CarouselItem => [:tagline]` back into the cleanup task's `TARGETS`.
- **Or stop making it Markdown-authorable** — replace the `Admin::MdEditorComponent` with a plain
  `f.input :tagline` text field, since a one-line carousel tagline arguably doesn't need Markdown.

Recommended: the plain-text-field route (a hero tagline is short and rarely needs block Markdown),
which also removes the heavyweight editor from a trivial field. Either way, resolve the
edit-as-Markdown / render-as-plain contradiction.

---

## RubyLLM legacy `acts_as` deprecation warning on boot (Phase B)

Since introducing `ruby_llm`, every process load prints:
`RubyLLM's legacy acts_as API is deprecated and will be removed in RubyLLM 2.0.0`.
We don't use `acts_as_chat`/`acts_as_message` (the Extractor and AiChecker call
`RubyLLM.chat` directly), so the warning is pure noise from the gem's Rails engine.
Investigate silencing it (config flag or a targeted `ActiveSupport::Deprecation`
filter) so test/boot output stays clean. Harmless; not gating.

## Multiple financial years — PLANNED (post-MySQL)
Now designed: a year-selector model (one active year + look-back), landing at the MySQL
cutover, not on Airtable. Full plan in `docs/reimbursements/mysql-migration-and-roadmap.md`
(financial_year FK on budgets/expenses/actuals, EUSA codes stay on CostCentre with a thin
per-year join only if they ever rotate, clone-into-next-year). Interim on Airtable: one base
per year, swap the base id if a new Fringe starts before the cutover. — Mick, 2026-07-12

## Reimbursements breadcrumb shows the raw Airtable record id

On a budget (and likely expense/batch) edit page the breadcrumb renders the record id
humanized — e.g. "Rec X Ko G9m U Fbu Dn5 A" instead of the budget name. The breadcrumb
crumb for a show/edit resource should use the record's display name (`@budget.name`), not
`to_param`. Low priority; spotted 2026-07-17 while linking the budget owners checkbox list.

## Deferred from the MySQL-cutover code review (2026-07-18, branch reimbursements-mysql-cutover)

- **Store-level attribute filtering instead of capability probes**: `MailboxPollJob#expense_attrs` still gates `source_message_id` on `store.supports_message_idempotency?`, and `DatabaseStore#batch_columns` silently `.except(:eusa_draft_created)`. The deeper fix is each store declaring/filtering its supported write vocabulary so callers always send full attrs. Both become moot at the post-flip cleanup when the Airtable store is deleted.
- **Post-flip cleanup list additions**: the review card's "Remove this receipt from Airtable?" confirm copy (`app/views/admin/reimbursements/review/_expense_card.html.erb`), and `ExpenseEditsController#lookup_expense`'s `"rec"`-prefix live-fetch special-casing (dead on the DB backend — `DatabaseStore#find_expense!` returns nil instead of raising).
- **Three hand-maintained bank-fields lists** (importer guard, `DatabaseStore::PAYMENT_DETAILS_FIELDS`, the test seed helper) could derive from one `PaymentDetails::FIELDS` constant.
- **ExpenseSemantics#receipt_count** still builds Attachment wrappers to count; `receipt_files.size` would be free on the AR side, but the shared module keeps the PORO shape until the POROs die.

## Per-worktree / per-subagent database isolation (dev + test) — spotted 2026-07-23

`config/database.yml` only **half** isolates today:
- **test:** `bedlam_blacklightning_test<%= ENV.fetch("WORKTREE_DB_SUFFIX", "") %>` — suffix exists
  but defaults to **empty**, so it only isolates when a worktree explicitly sets
  `WORKTREE_DB_SUFFIX` *and* provisions its own test DB (schema-load). Nothing sets it
  automatically.
- **dev:** the `development:` primary/queue/cache databases are hardcoded with **no suffix**, so
  every worktree (and every `bin/dev`) shares one dev DB.

Consequence: parallel background **subagents** running `bin/rails test` against the single shared
test DB truncate each other's fixtures, and parallel dev servers share dev data — which is why the
current working rule is "serialise agent test runs / go sequential" (see the global memory note
`hk-stash-vs-background-agents`). That's a workaround, not a fix.

**Improvement — make the DBs subagent-compatible:**
1. Extend the `WORKTREE_DB_SUFFIX` interpolation to the three `development:` databases too (or a
   parallel `DEV_DB_SUFFIX`), so a worktree/subagent can run an isolated dev stack.
2. Auto-provision on worktree creation: a setup step that derives a stable suffix from the
   worktree/branch name, then **creates the worktree's dev + test DBs by cloning from the current
   `main` dev DB** (or schema-load + seed if a clone is too heavy), so a fresh worktree comes up
   with data without manual `db:prepare`.
3. Do the same for background subagents dispatched in parallel: give each its own suffix + DB so
   fix-agents can run tests concurrently without the serialise-or-clobber constraint. This is the
   piece that removes the `hk-stash-vs-background-agents` limitation.
4. This is exactly what the `dev-hooks:worktree-setup` skill's `.worktree-isolate.conf` mechanism
   is designed to drive (per-worktree ports + DBs), which isn't configured in this repo yet —
   wiring it up is likely the cleanest path, plus upstreaming any gaps into that skill. Also update
   the `parallel-worktree-dev-server-ports` global memory note once done.

## Budgets index intro copy still says the financials come "from Airtable"

`app/views/admin/reimbursements/budgets/index.html.erb` opens with "Every budget category
from Airtable with its live financials … Those five are Airtable rollups, shown read-only
here." The Airtable backend is gone (Track A) and every figure is now computed in
`Reimbursements::Budget` from the local tables. The copy is also out of date on the count:
the table shows nine rollup columns since Track G, not five.

**Fix:** reword to describe the rollups as computed by the portal, and drop the Airtable
reference. Noticed while adding the Budgets CSV export (Track H); left alone there because
the Fringe/copy sweep (Track D) owns user-facing prose.

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

## `AmountValidation` is a fourth, stricter money parser

The 2026-07-25 round consolidated the three lenient decimal parsers (ExpenseForm and the two
budget controllers) into `Reimbursements::AmountParser`. `Reimbursements::AmountValidation`
(used by Review#save and ExpenseEditsController#update) still has its own `DECIMAL_FORMAT` +
`Float()` reading, deliberately stricter: it rejects anything that isn't a plain decimal so
`Float()` and `String#to_f` can never disagree on the value that reaches the write path.

That's a defensible reason to differ, but the upshot is that the *finance* edit forms reject
"£1,200" while the submitter form and the budget forms accept it. Worth a look at whether
those two paths should parse with `AmountParser` and then validate the parsed BigDecimal
(rather than validating the raw string), so "what counts as an amount" is one answer across
the portal.
## The encryption backfill task cannot run once `support_unencrypted_data` is off, and says so only in a summary count

`lib/tasks/reimbursements_encrypt_backfill.rake` rescues per row and prints
`processed 0/1 (1 failed)`, then still finishes with the cheerful "Done. Verify a sample
row's raw column is ciphertext, then flip …" line and exit status 0. Observed while adding
the T2 rollout tests: with `config.active_record.encryption.support_unencrypted_data = false`
the task can no longer *read* a plaintext row, so every row fails and nothing is encrypted —
the exact state an operator reaches if they flip the flag before backfilling (the order
`docs/reimbursements/encryption-rollout.md` prescribes, but nothing enforces).

**Fix:** exit non-zero when any row failed, and don't print the "flip the flag" advice on a
run that had failures. Optionally refuse to run at all when `support_unencrypted_data` is
already false, naming the flag.

## `PersonLink`'s stale-stored-link branch is unreachable in-app

A real FK (`add_foreign_key "users", "reimbursements_people"`) plus
`has_one :user, dependent: :nullify` on `Reimbursements::Person` mean a user's
`reimbursements_person_id` can never dangle through any application path — deleting a payee
nullifies the FK instead. `PersonLink#person_for`'s fall-through therefore only defends
against DB-level damage (a restore or maintenance script with `FOREIGN_KEY_CHECKS=0`).
Worth keeping (its failure mode is a duplicate payee with the wrong bank details), but the
review's framing of it as an everyday path is wrong. `test/services/reimbursements/person_link_test.rb`
now covers it by reproducing the orphan with referential integrity disabled, and says why.

## `users#autocomplete_list` test is intermittently flaky on Faker name collisions

`test/functional/admin/users_controller_test.rb:262-263` asserts that the excluded
non-member's `first_name`/`last_name` do **not** appear in the response body, and the
assertions carry their own admission: *"Ocassionally fails if the first name is not unique"*.
Faker can hand one of the seeded members the same first (or last) name as the excluded user,
and the substring assertion then fails even though the controller behaved correctly. It dates
to `4bf54a12` (2020-06-01) and surfaced again during the 2026-07-25 cleanup, passing on re-run.

It is a real intermittent CI risk: a red pipeline that means nothing, which trains people to
re-run rather than read failures.

**Fix:** assert on identity rather than on name substrings. The row already carries the user id
(`assert_not_includes response.body, user.id.to_s` on the next line is the assertion that
actually holds), so the two name assertions can either be dropped as redundant or replaced with
a parsed-response check that the excluded user's *record* is absent. If the names are worth
asserting, generate them explicitly (e.g. `"Zzz Excluded"`) instead of leaving it to Faker.
Related: the same Faker-versus-`response.body` trap bites differently when a name contains an
apostrophe, since the body is HTML-escaped.
