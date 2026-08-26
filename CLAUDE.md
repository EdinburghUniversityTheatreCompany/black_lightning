# Black Lightning - Claude Code Guidelines


## Packages
Ruby on Rails 8.1 

Use pnpm for package management rather than npm, yarn, or bun. The pnpm version is pinned in
`package.json`'s `packageManager` field (the single source of truth) and provided by **corepack**:
the dev container and host enable it via the `corepack enable` mise `postinstall` hook (`mise.toml`,
requires `experimental = true`), and CI's `pnpm/action-setup` reads the same field (no `version:`
pin). To bump pnpm, run `corepack use pnpm@<version>` (it rewrites `packageManager` with a fresh
integrity hash) — do not hand-edit the hash.

We use minitest for testing.

The entire site currently uses Tailwind v4

Use stimulus for all JavaScript sprinkles. We use Vite rather than jsbundling, cssbundling and importmaps. We use propshaft too to serve some images and JavaScript files that are only used on a few pages

## JavaScript
Prefer writing Stimulus controllers that go into the `app/javascript/controllers` folder. Custom modules go into the `app/javascript/lib folder`.

JavaScript that is only used on specific pages should go into the `app/assets` folder so it can be loaded by Propshaft.

Stylesheets also live in `app/javascript/styles` so they can be handled by Vite.

Third-party CSS/JS vendored verbatim (not authored by us, not meant to go through Tailwind/PostCSS)
goes in `vendor/assets/{stylesheets,javascripts}` instead of `app/assets` — Propshaft auto-registers
that directory too, and it's already excluded from jscpd/duplication scanning via the blanket
`**/vendor/**` glob in `.jscpd.json`, so no per-file exclusion entry is needed.

## Maintain Documentation

If you learn something about the project that would be useful context for other agents looking at the codebase, add it to this file at the end of your to do list.

## URL as state
Always maintain the URL as state with readable parameters where possible for GET actions.

## Button Styling

`ButtonComponent` (`app/components/button_component.rb`) is the single source of truth for all button styles. **Never use Bootstrap `btn btn-*` classes** — those shims have been removed.

### Variants: `:primary`, `:secondary`, `:danger`, `:success`, `:warning`, `:info`, `:link`
### Sizes: `:sm`, `:md` (default), `:lg`

### How to render a button

**Model resource links — use `get_link` (handles permissions + path generation):**
```erb
<%= get_link(@user, :edit) %>
<%= get_link(@user, :destroy) %>
<%= get_link(User, :new) %>
<%# Override variant explicitly %>
<%= get_link(@user, :show, variant: :primary) %>
<%# Custom link target for nested routes %>
<%= get_link(Admin::Feedback, :new, link_text: "Submit Feedback", link_target: new_admin_show_feedback_path(@show)) %>
```

**Non-model links — use `link_to` with `btn_classes`:**
```erb
<%= link_to "Cancel", some_path, class: btn_classes(:secondary) %>
<%= link_to "Import", new_admin_membership_import_path, class: btn_classes(:primary, :sm) %>
```

**Form submits — use `btn_classes`:**
```erb
<%= f.submit "Save", class: btn_classes(:primary) %>
<%= f.button :submit, "Agree", class: btn_classes(:success) %>
```

**Inside ViewComponent templates — use `ButtonComponent.classes_for` directly** (components don't get helpers auto-included):
```erb
<%= link_to "Cancel", @cancel_path, class: ButtonComponent.classes_for(variant: :secondary) %>
<%= f.submit "Save", class: ButtonComponent.classes_for(variant: :primary, size: :sm) %>
```

**To change a colour or add a variant, edit only `ButtonComponent::VARIANT_CLASSES`.**

## Link Helper

**Use `get_link` from `LinkHelper` for button-style links to model resources.**

The `get_link` helper provides:
- Consistent styling via `ButtonComponent` based on action type (auto-detected)
- Automatic CanCanCan permission checking
- Automatic path generation for model resources

## ViewComponents
When writing a ViewComponent, check for an applicable skill, and make sure to create a preview to pass the cop.

## Dev Environment (mise + hk)

Toolchain is pinned with **mise** (`mise.toml` + committed `mise.lock`; `hk`, `pkl`, `gitleaks`,
`node 24.13.0`). Pre-commit checks run through **hk** (`hk.pkl`) — this **replaced overcommit**
(`.overcommit.yml` and the `overcommit` gem are gone). After pulling these changes, run
`mise install && hk install` once to swap the git hooks over.

- **Ruby is installed precompiled, not built from source.** `mise.toml` pins
  `ruby = { version = "…", compile = false }`, so mise downloads a precompiled portable Ruby from
  **jdx/ruby** (its default provider) instead of compiling via ruby-build — a ~12s download vs
  minutes. jdx/ruby's Linux builds run in manylinux2014 containers (glibc 2.17 floor) and bundle
  their own OpenSSL/libyaml/libffi, so the binary is portable across glibc ≥ 2.17 (the Debian-trixie
  devcontainer + CI are fine) and needs no build toolchain *for Ruby*. `compile = false` is set
  explicitly so a contributor's global mise `compile` default can't flip `mise.lock`. The devcontainer
  still ships a C toolchain + headers because the app's **native gems** (bcrypt, mysql2, nio4r, puma, …)
  are compiled by `bundle install`. Only `linux-x64`, `linux-arm64`, and `macos-arm64` have jdx/ruby
  builds; `macos-x64` (Intel Mac) falls back to a source compile.

- **Run all checks** (what CI mirrors): `hk run check`. Autofix: `hk run fix`.
- **hk steps:** `rubocop` (+`rubocop-minitest`), `eslint` (Stimulus JS), `herb` (ERB),
  `annotate-models` (see below), `brakeman`, `bundler-audit`, `fasterer`, `database_consistency`,
  `debride`/`flay`/`jscpd` (dead-code + duplication), `gitleaks`, `actionlint` + `zizmor`
  (GitHub Actions correctness + security), exec-bit + large-file guards, and `versions`
  (toolchain-drift guard — mirrors the CI `versions` job; keep the two in sync by hand).
  `bin/rails test` also runs as an hk step.
- **`annotate-models` is a fix-only pre-commit step**: committing a model or `db/schema.rb`
  auto-regenerates the `# == Schema Information` blocks via `annotaterb models`. It DB-probes and
  skips cleanly when no dev/test DB is reachable, and never runs as a CI gate.
- **Gate status (see [plans/off-topic-improvements.md](plans/off-topic-improvements.md)):**
  `herb-lint` (ERB) and `jscpd` (duplication, threshold 0) are **gating** — their backlogs were
  ratcheted to 0. `herb-analyze` stays advisory (`|| true`) only for the two HTML-email fragment
  partials it can't parse standalone. `database_consistency` is still advisory: its length
  validations are satisfied and the legacy integer-PK checkers are scoped in `.database_consistency.yml`,
  but the remaining NOT-NULL / FK / unique-index findings need data-aware backfill migrations on the
  legacy DB (a documented follow-up). Two herb rules are intentionally disabled in `.herb.yml`.
- **Secrets:** `gitleaks` scans the whole tree; gitignored secret/runtime paths are allowlisted in
  `.gitleaks.toml`. Real plaintext secrets still live in `config/` — consider migrating to fnox.
  The **CI `gitleaks git` job scans full history** (the hk step only scans the working tree), so
  it surfaces dead secrets committed years ago. Reviewed historical findings that are NOT live
  (doc examples, PEM marker lines, rotated/dead keys) are baselined by fingerprint in
  `.gitleaksignore` (each entry commented with why) — the default ruleset still fails on any NEW
  secret. We deliberately don't rewrite history to purge them: they're all dead, and it would
  reSHA ~3900 commits (back to the 2012 root) while GitHub may still cache the old objects.
- **Large-file guard:** committed files over 512 KB fail CI's `audit` job (and hk's
  `check-added-large-files`). PNG illustrations that trip it compress well as PNG8 palette
  (`convert … PNG8:out.png && optipng -o5`) with no visible loss — they're flat-colour art.
- **The dev container is mise-driven — keep it in sync.** [.devcontainer/Dockerfile.dev](.devcontainer/Dockerfile.dev)
  installs *only* the `mise` binary plus OS build/runtime libs; `mise.toml`/`mise.lock` are the single
  source of truth for Ruby, Node, and the dev tools, installed by `mise install` in
  [.devcontainer/setup.sh](.devcontainer/setup.sh). **Never** pin a language version in the devcontainer
  (no `ruby:x.y` base, no `apt-get install nodejs`) — that reintroduces drift. When you change the
  toolchain (a new mise tool, a Ruby/Node bump) or the dev-env standard (`DEV_ENV_VERSION`), check
  whether the devcontainer needs a matching change: new native build deps go in `Dockerfile.dev`, new
  bootstrap steps go in `setup.sh`. The mise toolchain is cached on the `mise-data` compose volume.

## Dev Server

- **Run with `bin/dev`** — foreman ([Procfile.dev](Procfile.dev)) supervising Puma (`bin/rails server`) + Vite (`bin/vite dev`). **Start one yourself when you need it** (a screenshot, a visual check, driving the real app) — this overrides the global "ask the user first" default. Check the port is free first (`ss -ltn | grep ":${PORT:-3000}"`) and run it in the background.
- **A provisioned worktree gets its own ports** — `PORT` and `VITE_RUBY_PORT` come from a gitignored `mise.local.toml` (see `.worktree-isolate.conf`), so a worktree's server never fights the main checkout's :3000. Run `bin/dev` from the worktree directory or you will start a second server on the wrong port against the wrong database.
- **Stop `bin/dev` before `bin/rails test:system`** — a running dev server makes ~57 unrelated system tests fail, and the failures point nowhere near the cause.
- **No restart needed for app code** — models, controllers, views, etc. are auto-reloaded on the next request.
- **To reload boot-time state** (`config/initializers`, `config/*`, `Gemfile`, env vars, new/enum-backed DB columns): run **`bin/restart-web`** — see its header comment for the mechanics and why `touch tmp/restart.txt` does nothing here.
- **For a full stack restart** (e.g. `vite.config` or JS dependency changes): `Ctrl-C` the `bin/dev` terminal and rerun it, or in VS Code run the "Dev server" task again (Tasks: Restart Running Task).

## Background jobs (Solid Queue)

- **`config/recurring.yml` schedules are read in `config.time_zone` ("Edinburgh"), not the
  container's clock.** Solid Queue ≥ 1.5 appends `SolidQueue.time_zone` (resolved from
  `config.time_zone` → `Europe/London`) to any schedule that names no zone of its own, so
  "at 9pm every day" means 9pm *Edinburgh*. Before 1.5 it meant 9pm in the process's local
  time, and the production container sets no `TZ`, so it meant 9pm UTC — i.e. every daily job
  now fires an hour earlier in UTC terms through BST, and unchanged through GMT. This is the
  reading the schedule names imply; to go back to clock time, set
  `config.solid_queue.time_zone = nil`.
- The queue schema is **schema-loaded, not migrated** (`db/queue_schema.rb`,
  `migrations_paths: db/queue_migrate`). `bin/rails generate solid_queue:update` copies any new
  gem migrations in — as of 1.6.0 it ships none, and our schema matches the gem's table set.

## Database & Migrations

- **Multi-database app.** `bin/rails db:rollback` errors with "must run the namespaced task". Use `bin/rails db:rollback:primary STEP=n` (namespaces: `primary`, `queue`, `cache`).
- **Legacy tables use integer primary keys, not bigint.** `opportunities` and other older tables have `id: :integer`. A new child table's foreign key to such a table must use `t.references :parent, type: :integer` (or `t.integer`), otherwise the FK migration aborts with a column-type mismatch. New tables you create default to bigint `id`, which is fine for FKs pointing *to* them.
- **The running dev server caches the DB schema at boot.** After a migration that adds columns, the already-running server will 500 (e.g. "Undeclared attribute type for enum ... must be backed by a database column") until it is restarted. Run `bin/restart-web` after migrating (see **Dev Server** above).

## Schema annotations

Models carry `# == Schema Information` blocks maintained by **`annotaterb`** (replaced the unmaintained, Rails-8-incompatible `annotate` gem). Config is `.annotaterb.yml`; the `lib/tasks/annotate_rb.rake` hook re-annotates models automatically on `db:migrate` in development. Regenerate manually with `bundle exec annotaterb models`. **Keep `:format_rdoc: false` (plain format)** — annotaterb's RDoc output is non-idempotent (it re-appends the Foreign Keys section + terminator on each run), causing endless churn. Only models are annotated (`exclude_factories/fixtures/tests: true`).

## Attachments — allowed file types

`Attachment::ALLOWED_CONTENT_TYPES` (`app/models/attachment.rb`) is the server-side allow-list for uploads (there is no browser `accept` filter). `active_storage_validations` resolves an upload's type via `Marcel::MimeType.for(declared_type: blob.content_type, name: blob.filename)` and **raises `ArgumentError` if an allow-listed string is unknown to Marcel** — so any type Marcel doesn't ship must first be registered in `config/initializers/sheet_music_mime_types.rb` (and the server restarted, since initializers are boot-time state). For **container-based** formats (zip- or xml-wrapped, e.g. `.mscz`/`.mxl`/`.musicxml`), register the type with the container as a `parent:` so Marcel keeps the specific type instead of resolving to bare `application/zip`/`application/xml` — otherwise you'd have to allow the bare container type, which would let *any* zip/xml through.

## Permissions

The permission grid auto-discovers models via `ApplicationRecord.descendants` in `Admin::PermissionsController#set_models_and_roles`. A new top-level model appears in the grid automatically; a nested child model managed only through its parent (like `OpportunityRole`, `MarketingCreatives::CategoryInfo`) should be added to the exclusion list there.

## Reimbursements portal

Producer-facing expense portal under `/admin/reimbursements`
(`Admin::Reimbursements::BaseController < AdminController`), gated by the grid
permission `access`/`reimbursements` (a symbol subject like `:backend`; listed in
`Admin::PermissionsController`'s miscellaneous permissions) and linked from the admin
sidebar's Finance category. Data lives in the local `reimbursements_*` MySQL tables
(`Reimbursements::{Expense,Person,Budget,…}` AR models, receipts on ActiveStorage). The
Airtable backend was retired in the post-flip cleanup — the `REIMBURSEMENTS_BACKEND`
switch, the `Reimbursements::Airtable::*` POROs, the Solid-Cache-fronted Airtable
`Store`, and the importer are all gone (see the "Done" note in
`docs/reimbursements/mysql-migration-and-roadmap.md`). The `airtable_record_id` columns
survive as historical import provenance and are never written. Spec + plan in
`docs/superpowers/specs|plans/`.

- **Everything goes through the store built by `Reimbursements.build_store`** — the
  AR-backed `Reimbursements::DatabaseStore`, the single data gateway with a frozen
  public API. No cache layer: lists are memoized per instance (one store per
  request/job run). `DatabaseStore::LastReceiptError` guards removing an expense's last
  receipt. Never hit AR models directly from controllers/jobs — go through the store.
- **Budget figures and the overview** (`Reimbursements::Budget`, `NominalCodeRollup`,
  `/admin/reimbursements/budgets/overview`):
  - **`eusa_actual_amount` is linkage-based and NET.** An Expense budget counts the actuals
    reconciled to its *expenses*, an Income budget the ones booked against its `budget_id`;
    matching on nominal code would be wrong because several budgets share a code. Both
    directions net through `EusaActual.net` (debits less credits, offsetting legs dropped),
    so a refund reduces a line instead of inflating it.
  - Because the rollups are linkage-based, the overview's second card
    (`DatabaseStore#unattributed_actuals`) is what stops unlinked spend disappearing: rows
    linked to neither an expense nor a budget, offsetting legs excluded. It is NOT
    "nominal code with no budget" — that older definition hid unlinked spend behind any
    budget sharing the code, and suppressed every blank-code row.
  - **Expense and Income budgets are never totalled together** (£10k spend + £8k income is
    not £18k of anything). Every total comes from `NominalCodeRollup#by_type`.
    **`expected_outturn` is nil for an Income budget** and renders blank/empty everywhere
    (overview, index, edit, CSV, xlsx): the "never below reality" max reads as *best-case*
    income on that side.
  - **`store.budgets` deliberately does NOT preload actuals** — only
    `store.budgets_with_actuals` does (budgets index/overview + the Budgets export sheet).
    Don't "fix" a caller by switching it: the producer's budget `<select>` used to load the
    whole expenses + actuals ledger to draw a dropdown.
- **Financial years** (`Reimbursements::FinancialYear`, `Admin::Reimbursements::FinancialYearsController`).
  Each Fringe recurs with its own budgets; a year is built as a **draft** (create → import its
  budgets → check) and switched to with `activate!`, never a checkbox on the edit form —
  activating changes every submitter's budget picker. `activate!` stands the incumbent down and
  promotes the target in one transaction (`only_one_active` rejects the record otherwise, and a
  target that fails to save must not leave the portal with NO active year).
  - **The selector is `?year=<key>` on the budget screens only** (`FinanceController
    #resolve_financial_year!`, defaulting to the active year; an unknown key alerts and falls
    back). Expenses, Review, Actuals, Batches and Reconcile are deliberately NOT year-scoped yet.
  - **Which store reads are scoped is the design, not an oversight.** `store.budgets` stays
    UNSCOPED — its callers are id→budget lookups (Review, the expenses index, every export, the
    nightly job) and the reconcile matcher, so scoping it would blank the budget name on last
    year's claims and stop the year-boundary tail of EUSA credits matching their income line.
    `budgets_for_year` / `budgets_with_actuals` / `budget_updates` are scoped.
    **`active_budgets` follows the ACTIVE year, never the selected one**, so a finance user
    browsing next year's draft can't file against it.
  - **A row with no year counts as belonging to the year being viewed** (`DatabaseStore#in_year`),
    the same leniency the reconcile matcher gives a budget with no cost centre: every row
    predating financial years is unstamped until `reimbursements:financial_year_backfill` runs,
    and the strict reading would empty the budget list and every submitter's budget picker with
    nothing on screen to explain it.
  - **`BaseController::DEFAULT_STORE_BUILDER` exists so a test can put the seam back.** The
    store seam now takes `financial_year:`; restoring it by hand as `-> { build_store }` drops
    the argument, and `class_attribute` makes that stick for the rest of the process — every
    later year-scoped page in that worker then renders every year's budgets at once.
- **Setting a year up = importing the committee's spreadsheet** (`Reimbursements::BudgetImport`,
  `Admin::Reimbursements::BudgetImportsController`, `DatabaseStore#import_budgets!`). Paste TSV or
  upload .xlsx (both via the shared `ImportParsing` concern, as the membership import does) →
  preview → apply. **Stateless like Reconcile**: an upload is normalised to canonical TSV
  (`BudgetImport#to_tsv`, escaping tabs/newlines inside a cell) and carried through the preview in
  a hidden field, so apply re-parses and re-validates rather than trusting the preview.
  - Buckets, matched by name within one `(financial year, cost centre)`: **create / revise /
    unchanged / invalid**, plus `absent_budgets` (in the year, not in the sheet) which is
    **reported and never deleted** — a budget's claims and history hang off it.
  - **`initial_budget` is written ONLY on create.** A re-import logs revisions as forecasts under
    one `BudgetUpdate`, so `Budget#variance` keeps meaning "drift from the figure the committee
    agreed" however often the sheet is re-sent.
  - **An unreadable amount blocks the whole import; an unknown owner email only warns.** A
    mis-read figure is silent wrong money; a stale committee email must not stop thirty lines
    landing, and a missing owner surfaces visibly as an unendorsed claim. No `Person` is ever
    auto-created from a bare email. `import_budgets!` is all-or-nothing (unlike Reconcile's
    per-row rescue): a half-imported list has no audit value, and re-running after a fix is cheap
    because matching is by name.
- **Typed money goes through `Reimbursements::AmountParser`** (`£1,200`, `12,50` comma
  decimal). `.parse` → nil for anything unreadable; **`.parse!` distinguishes blank
  ("nothing typed", nil) from unreadable (raises)** — the batch budget-update form needs
  that to tell a deliberate blank from a typo, since treating both as "skip" silently kept
  a budget on a superseded forecast. **`AmountValidation` (Review#save, expense-edit
  #update) reads through the same parser** and adds the finance rules on top: positive,
  within `MAX_AMOUNT` (100k, the fat-finger backstop), excl-VAT not above gross. Its
  callers must write `AmountValidation.amount` / `.amount_excl_vat` — the parsed
  BigDecimal — never the raw param: AR casts a string to a decimal column with `to_d`, so
  a validated "£1,200" handed through raw would store **0**.
- **Secrets** (`Reimbursements::Settings`): `REIMBURSEMENTS_*` ENV first (dev: fnox —
  the *development* credentials are publicly readable, so no secret values there), then
  per-env credentials `reimbursements:` (production only).
- **Outbound Graph calls are gated to production** (`Settings.outbound_enabled?`): true in
  production, elsewhere only with `REIMBURSEMENTS_ENABLE_OUTBOUND` set (the test suite opts in
  via `test_helper.rb`, since it fakes the transport). **This is why email-in appears to do
  nothing locally — by design, not a bug.** `MailboxPollJob#perform` returns immediately;
  `send_mail` and `create_draft` log and return a stub; `MailboxClient#reply/#move/#mark_read`
  no-op. `upload_to_folder` and `delete_message` instead **raise** `OutboundSuppressedError`,
  because a plausible return value there is indistinguishable from success and would stamp
  `receipts_offloaded` on receipts that were never backed up (the flag that tells a producer it
  is safe to delete their only copy). Read-only Graph probes stay live in dev, so the Settings
  integration dashboard still works. Without this, a dev machine holding fnox Azure credentials
  would email real producers and PUT the BACS spreadsheet into production SharePoint.
- **Bank details are encrypted at rest** (ActiveRecord Encryption, non-deterministic):
  `sort_code`/`account_number`/`notes` on `Reimbursements::PaymentDetails`, and the
  `sort_code_override`/`account_number_override`/`payee_name_override` trio on
  `Reimbursements::Expense`. Nothing queries these by value (non-deterministic would break that);
  the money path reads the decrypted attributes. Keys: production credentials under
  `active_record_encryption:` (Rails' railtie reads them automatically); development takes
  `REIMBURSEMENTS_AR_ENCRYPTION_*` from ENV (fnox) **falling back to throwaway literals in
  `config/application.rb`** — needed because an encrypted attribute requires a key on write even
  when blank, so without them every `Expense.create!` in a fnox-less dev shell raised; test uses
  literals in `config/environments/test.rb`. `development.key` is *committed*, so real key
  material must never go in `development.yml.enc`.
  - **The rollout is complete** (production backfilled 2026-07-26; every value in all six columns
    verified as ciphertext). `support_unencrypted_data = false`, so a stray plaintext value now
    **raises** rather than being served, and **there is no rollback**: removing `encrypts` would
    make the stored data unreadable, and losing the production credential keys loses the bank
    details outright. **Encrypting a NEW column repeats the whole sequence**, because
    `reimbursements:encrypt_backfill` cannot run while the flag is false (it must read the
    plaintext to rewrite it): add `encrypts`, flag true, deploy, backfill, verify, flag false,
    deploy. The backfill aborts non-zero on any failed row, since flipping the flag over an
    unconverted row makes it unreadable. Sequence and the all-rows verification sweep in
    [docs/reimbursements/encryption-rollout.md](docs/reimbursements/encryption-rollout.md).
  - Rails' auto-injected `validate_column_size` guard is **off** (`config.active_record.encryption
    .validate_column_size = false`): it measures the *decrypted* value, so it never caught the real
    hazard, and it crashed `database_consistency` on both models. Explicit plaintext length caps on
    the models do that job instead. Ciphertext runs roughly 2× plaintext plus envelope, which is
    why `payee_name_override` had to become TEXT.
- **An Invoice claim must carry the third-party payee trio** (`ExpenseForm#invoice_without_payee?`).
  `expense_type == TYPE_INVOICE` means EUSA pays the supplier, so blank overrides are a money
  bug, not a gap: `EffectivePayee` falls back to the **submitter's own** bank details, which
  `ReviewSupport`'s "no bank details" block then reads as satisfied — so the claim would
  quietly pay the producer for a bill they never paid. It is a submit-time
  block only (drafts and email-in still save incomplete), and the message names Reimbursement
  as the type for a bill they paid themselves. **The finance edit form applies the same rule**
  (`ExpenseEditsController#expense_type_error`) but only while
  `ReviewSupport.attention_actionable?` — Draft/Pending/Approved, where the money can still
  move. Submitted and Paid records must stay re-typable without inventing bank details for a
  supplier we never captured. That form is also the only place `expense_type` can be changed
  after submission (and the only one offering From EUSA), so a mis-typed claim no longer needs
  the producer to withdraw and resubmit.
- **`:base` errors are rendered by `shared/pages/_form`**, not by simple_form: `f.error_notification`
  is only the generic "review the problems below" banner and has no field to hang a base error
  under. Anything added with `errors.add(:base, …)` on a form rendered through that partial is
  visible; a form NOT using it (bare simple_form) still needs its own rendering, or the rule
  fails the submit with no stated reason.
- **There is no AI in this portal, by decision (removed 2026-07-31).** The Gemini receipt
  extractor (`Reimbursements::Extractor`, an opt-in prefill behind a consent radio group) and
  the finance `AiChecker`/`AiCheckJob` verdict were both removed outright, along with
  `PromptSafety`, the `ruby_llm` gem, the `gemini_api_key` setting and the four `ai_*` columns
  on `reimbursements_expenses`. **Don't reintroduce it casually**: the disclosure it required
  told producers we sent their receipts — and, on an invoice, a supplier's printed bank
  details — to Google's *free* tier, where Google may keep a copy and have people read it.
  The submission form is manual, which it always was underneath: consent was deliberately
  never server-validated so the form stayed submittable with JavaScript off.
  **The VAT soft-block in `ExpenseForm` stays a soft block**, now triggered only by the ex-VAT
  amount not being below the total (`vat_itemised` was extractor-written and went with it).
- **The nightly job reminds, it never gates** (`Reimbursements::NightlyBatchJob`). It submits
  nothing and builds no batch — Build Batch is operator-initiated. Per due run-day it sends two
  independent reminders for the default cost centre: stale **Pending** claims awaiting approval,
  and the whole **Approved** queue ready to batch. Claims `ReviewSupport.needs_attention` flags
  are listed inside the approved reminder *with their reasons*, never held back: the older
  behaviour swapped the whole list for a "manual review" email, so one problem claim hid every
  other claim from the operator. A reminder with nothing to say counts as delivered.
  - **`record_nightly_run!` is gated on EVERY reminder having sent**, from one call site. That
    write marks the run-day handled forever (`nightly_due?` skips it) and there is no retry
    queue behind these alerts, so a half-sent run must be retried whole — at the cost of
    re-sending the reminder that worked, uncapped — a multi-day Graph outage re-sends it
    nightly, which is the intended direction (duplicates over silence). Both reminders are
    always *attempted*: `deliver_reminders` collects them into an array and calls `.all?`
    precisely so the calls cannot short-circuit. Don't rewrite it into a boolean expression.
  - Both reminders sit behind the default-cost-centre guard because expenses carry no
    cost-centre link yet, so both queues are global and a second due centre would double-send.
- **Email-in**: `Reimbursements::MailboxPollJob` (recurring, every 5 min) polls the
  shared mailbox via `MailboxClient` (Graph app-only auth, scoped by an
  ApplicationAccessPolicy). Every inbound receipt becomes a **blank DRAFT** (subject as the
  description, amount/budget/reference left blank) plus the "please complete it in the
  portal" reply.
  Reply-then-move is the commit point; unread = will retry.
  `CredentialsCheckJob` (daily) + `AuthError` alerts warn `alert_email` (IT
  subcommittee) before/when the Entra client secret dies.
- **Every producer email greets by FIRST name through `Reimbursements::GreetingName.for`**
  — the one derivation, because the two surfaces are written differently and must not
  drift: the `Notifier`'s two producer templates (rejection, producer_notification)
  are ERB, while `MailboxPollJob`'s replies are plain-Ruby
  heredocs. It prefers the **linked `User#first_name`**, then the leading word of
  `Person#name`, then `"there"` — the last because `PersonLink` stores the user's *email*
  as the person name when they have no full name, so a bare split would open with "Hi
  alice@example.com,". Callers derive the string and pass `greeting_name:`; the Notifier
  itself stays ActiveRecord-free (`payee_name:` inside the operator-alert **row hashes**
  is a different thing and still a full name, as is the BACS spreadsheet's payee). The
  heredoc replies escape it (`ERB::Util`) — they have no escaping of their own and
  `first_name` is self-service editable. `unknown_sender_html`/`rate_limited_html` keep a
  bare "Hi," on purpose: no matched person to name.
- **Tests**: seed real rows with the `create_reimbursements_*` helpers
  (`test/support/reimbursements_test_helpers.rb`). Pure-logic unit tests that need a
  value object without a DB round-trip build an unpersisted AR model and pin the
  DB-computed readers per-instance (`define_singleton_method(:record_id) { … }`,
  `instance_variable_set(:@receipts, …)`, `build_payment_details`). External services
  stay faked (FakeHttp, FakeGraphClient) through `class_attribute` builder
  seams on `Reimbursements::BaseController` and the jobs. No webmock. Don't name a test
  helper `message` — it collides with Minitest's internal `message(msg, ending)`. A dev
  shell's fnox-exported `REIMBURSEMENTS_*` vars leak real credentials into tests — strip
  them when running the suite by hand.
- **BACS batch invariants** (`Reimbursements::BatchProcessor`): the vendored xlsx
  template (`lib/reimbursements/templates/EUSA_BACS_template.xlsx`) caps a batch at
  `BacsXlsx::MAX_ROWS` (200) data rows — its GRAND TOTAL formula and the Authorisation
  Form's cross-sheet total only cover that range, so a bigger batch raises `TemplateError`
  rather than silently corrupting the total. `BatchProcessor#process`'s `result.success`
  reflects whether *every* expense actually reached `Submitted` (not just whether the EUSA
  draft was created) — a `mark_submitted` failure is the one exception to "post-draft steps
  are best-effort," since it leaves that expense in the same double-draft danger the
  orphan-draft guard exists to prevent. `BatchesController#reopen` won't revert/delete a
  batch unless Graph positively confirms the stored draft is still unsent — a batch whose
  draft was already sent by hand in Outlook must never be silently rebuilt into a second
  live submission.
- **Exports** (`app/services/reimbursements/exports/`): one exporter per resource
  (`Expenses`, `Actuals`, `Budgets`, `People`, `Batches`) under `Exports::Base`, each
  owning its `HEADERS` and a private `#row` **once**. That single definition drives both
  the per-view "Download CSV" (`FinanceController#send_export`, called from each index's
  `format.csv`, with the link built as
  `request.query_parameters.merge(format: :csv)` so the on-screen filters carry through)
  **and** the matching sheet of the combined workbook (`Exports::Workbook`,
  `ExportsController#show` at `GET /admin/reimbursements/export`). Add a column in the
  exporter, not in a controller. Conventions: amounts stay numeric (no "£"), dates are
  ISO 8601 strings with blanks left empty (not the on-screen "-"), and **every cell goes
  through `Reimbursements::CellSanitizer`** — the shared formula-injection guard that
  `BacsXlsx` uses too. `Base#add_sheet` pins every String cell to Axlsx `:string`, or a
  numeric-looking identifier is coerced to a number (nominal code `041000` → 41000,
  period `03` → 3). **Bank details in an export are masked to their last four digits**
  via `BankDetails.mask` (also used by the People notes audit line); only the BACS
  spreadsheet EUSA pays from carries full numbers.
- **Receipts are served by the app, never over ActiveStorage's routes**
  (`Admin::Reimbursements::ReceiptFilesController`). Those routes are
  unauthenticated and permanent by design, and a receipt carries a home address, so
  a link would have worked forever for anyone who came by it. `Attachment#attachment_id`
  is therefore the **blob id, not the signed id** — the signed id is a bearer token for
  those routes and must never reach the markup; `remove_receipt!` matches on the same id.
  Streamed rather than redirected (the viewer's `<img>`/`<iframe>` must stay same-origin
  under the CSP, and Chrome's PDF viewer wants byte ranges) and cached `private`.
  Visibility is the union of finance, the submitter, and the budget's owners; anything
  else 404s rather than 403s.
- **`ReceiptIntake` strips metadata from every raster receipt**, re-encoding in the
  same format rather than excising the EXIF segment: coordinates hide in EXIF GPS, XMP,
  MakerNotes and the embedded thumbnail, so only a re-encode is provably complete. PDFs
  pass through byte-for-byte. A side effect worth knowing: Marcel falls back to the
  filename when the magic bytes match nothing, so bytes that merely claim to be a PNG
  now have to decode as an image and are rejected if they don't.
- **Bank details are cleared after six months without a claim**
  (`Reimbursements::BankDetailsRetention`, nightly). **`TERMINAL_STATUSES` is stated as
  the terminal set, not the live one, on purpose**: an unrecognised status counts as live
  and blocks the clearing, because reading a claim as finished when it isn't wipes details
  about to be paid with no undo. Deleting a `User` destroys the linked payee's
  `PaymentDetails` outright (`User#erase_reimbursements_bank_details`, following the stored
  link *then* the email, as `PersonLink` does) — the Person and their claims stay, being
  financial records. Preview with `reimbursements:bank_details_retention_preview` before
  trusting a rule change; there is no rake entry point for the sweep itself.
- **On-screen bank details are masked until revealed**
  (`Admin::Reimbursements::BankDetailsComponent`). A **disclosure** control, not an access
  control — the full pair is in the markup behind the toggle, and everyone on those screens
  is entitled to it. The People registry is the exception: its fields hold the real values
  so they can be edited, so they are `type="password"` toggled to text — masking the value
  would invite saving `****4958` as an account number.
- **Reconcile emails nobody, by decision (removed 2026-08-12).** Marking an expense Paid there
  used to send the producer a "EUSA has paid your expense" note (`Notifier#payment_confirmation`
  plus its template, both gone). Reconciliation runs off EUSA's monthly actuals export, which
  lands weeks after the BACS run it confirms, so the note reached people who had spent the money
  already. The one payment-side email a producer gets is `producer_notification`, sent when
  their claim goes into a batch. Paid is a bookkeeping state here, not an event to announce, so
  don't wire a notification onto it again.
- **EUSA actuals — offsetting pairs + conversion.**
  `Reconciliation.detect_offsetting_pairs` finds the accrual/reversal legs that cancel out
  in a pasted export. **The governing asymmetry for every judgement call here**: a false
  positive stamps real spend as offset, which hides it from the ledger view and every
  rollup, while a false negative just leaves rows visibly unmatched for a human. Prefer
  missing a pair over inventing one.
  **Hard requirements**: same absolute amount (exact BigDecimal), opposite sign, **same
  nominal code**, same financial year. Survivors are **scored** (ref 4, nominal 2, period 1,
  narrative prefix 1, minus a date-distance penalty of 1 or 2) and taken greedily from the
  strongest, with a floor of 4 — so with the nominal gate every candidate starts at 2 and
  must find 2 more points (ref alone is 4 *minus* the date penalty, so a ref match on its
  own only clears the floor same-day). The weights are tuned against a real 309-row F40
  export: refs match only about half the time and legs straddle months, so neither can be a
  hard filter, but the nominal code *is* one (a Sage payment-run ref stamped across a run
  otherwise scored 5 pairing a cost with unrelated income of the same size). Verified on
  that export: 58 pairs with the gate, 58 without, none cross-nominal, so the tightening
  costs nothing.
  The preview shows every pair as a **ticked checkbox** keyed by row *content plus an
  occurrence index* — content alone collapses two byte-identical pairs into one vote (that
  export contains a byte-identical row group), and the occurrence index survives rows
  shifting position, which a bare row index would not. A key that fails to match on apply
  reads as unticked, the safe direction. Each pair also states what unticking it would pay,
  because the "N matched expenses" count covers the unpaired rows only. Applying imports
  both legs and stamps each `reconciliation_status: "offset"` + `offset_of_id` at the other
  in **one transaction** (`DatabaseStore#create_offsetting_pair!`: a half-written pair leaves
  the debit leg reading as real spend, and re-pasting can't repair it because dedup then
  skips that leg). Rows are never deleted, finance needs the audit trail — and a
  mis-detected pair is undone with the finance-gated **"Not offsetting"** button on the
  Actuals index (`ActualsController#unoffset` + `DatabaseStore#unlink_offsetting_pair!`).
  **An offsetting leg is never convertible to an expense** (`EusaActual#convertible_to_expense?`,
  Mick's call): it nets to zero, so converting it would invent spend. Unlinked *debit* rows
  can be converted (`ExpenseForm.from_actual` + `ActualsController#new_expense/#create_expense`),
  created **directly Paid** with `payment_confirmed_date` from the row so they never enter
  review/batch. The conversion goes through `DatabaseStore#create_expense_for_actual!`, which
  creates the expense and links the row in one transaction and **re-takes the convertibility
  check inside it under a row lock** — the controller's own check is a read that goes stale on
  a double-submitted form, and an expense created without its back-link leaves the row still
  offering "Create expense", so the next click double-counts the same EUSA charge.
  `NotConvertibleError` surfaces as a redirect saying nothing was created twice. `from_actual` sets an `internal` flag that admits `TYPE_FROM_EUSA` and
  relaxes the receipt/VAT/large-amount blocks; it is deliberately **not** a permitted
  parameter on the producer form, so a submitter can't pick the internal type to dodge the
  receipt rule.

## Crypt climate monitor

Temperature / humidity / dew point charts at `/admin/climate`
(`Admin::Climate::BaseController < AdminController`), gated by the `climate` grid permission
(`read` to view, `manage` to configure sensors and import). Runbook:
[docs/climate/csv-import.md](docs/climate/csv-import.md).

- **Crypt readings arrive by CSV import, NOT by polling the Govee API, and that is a
  correctness decision rather than convenience.** The Developer API has no history endpoint, and the
  crypt's WiFi is intermittent: the sensor buffers regardless of connectivity and uploads on
  reconnect, but a poller can only sample the present, so everything buffered during a dropout
  stays invisible to it forever. The export contains all of it. Don't reintroduce polling.
  The **dressing room access point** (installed early August 2026) gives the crypt sensors an
  intermittent WiFi path, so they upload to Govee's cloud without anyone standing there with the
  app open. That does not change any of the above: the connection still drops, the sensor's own
  buffer is still what survives the gap, and the API still has no history endpoint.
- **The CSV header names its own unit** (`Temperature_Celsius` / `_Fahrenheit`, following what
  the *app* displays). `Climate::CsvImport` reads it and **refuses a file whose unit it cannot
  identify** rather than guessing. That refusal replaced the old per-sensor verify-the-unit
  flow, and it is the whole defence against storing Fahrenheit as Celsius.
- **`Climate::ReadingIngest.upsert_series!` is the only write path**, shared by the manual
  import, the mailbox job and the outdoor poller. It owns the plausibility guard
  (-20..50 °C, 0..100 %), the dew point, and the idempotent `upsert_all`. Re-importing an
  overlapping export is normal and harmless.
- **Import is one step, not a preview wizard.** No per-row decisions exist, a 2-year backfill is
  far past what a hidden-field round trip carries, and it is the same code path the mailbox job
  calls, so manual and automatic cannot drift.
- **Email ingest**: `Climate::MailboxPollJob` (every 15 min) reads CSV attachments from
  `CLIMATE_MAILBOX` over Graph. ActionMailbox is NOT installed and M365 has no inbound webhook,
  so this reuses the existing Graph poll instead of new ingress. **Which sensor a file belongs
  to** falls back to the sole sensor, and anything ambiguous is left UNREAD and logged rather
  than guessed.
- **Graph plumbing is shared**: top-level `GraphAuth` + `Graph::MailboxClient` + `Graph::Settings`
  (which reads `GRAPH_*` and falls back to `REIMBURSEMENTS_AZURE_*`, because there is one Entra
  app for the org and renaming would have broken every existing credential entry).
  `Reimbursements::MailboxClient` is a thin subclass pinning the cost-centre default and its
  error-constant names.
- **Outdoor data self-heals, which is why Open-Meteo won.** `OutdoorPollJob` asks for a rolling
  `past_days` window hourly and upserts the lot, so an outage fills its own gap. Attribution
  (CC BY 4.0) is a licence condition and is rendered on the dashboard, and the free tier is
  non-commercial only. `Climate::OUTDOOR_SOURCES` is the swap point for Met Office / METAR.
  - **That self-healing is also why a failed poll only reaches Honeybadger once the line has
    been missing for a day** (`OutdoorPollJob::REPORT_FAILURE_AFTER`). The free tier sheds load
    with the odd 503, and the next successful poll re-serves the window, so a single failure has
    cost nothing yet — reporting it is noise. Every failure is still logged and written to
    `last_error`, which is what the dashboard's staleness badge reads (a tighter 3h window, per
    `Sensor::STALE_AFTER`). Never having had a reading counts as missing.
- **The outdoor sensor row is ensured by `Climate::Sensor.outdoor_source!`, not a data
  migration**, because test and CI databases are schema-*loaded*, so a data migration never
  runs there.
- **`Climate::SeriesQuery` must not bucket with `UNIX_TIMESTAMP`.** The mysql2 adapter doesn't
  pin the session `time_zone`, so that reads the stored value in the *server's* zone and shifts
  every bucket boundary by its offset. It uses `TIME_TO_SEC(TIME(recorded_at)) % n` instead,
  keyed off a frozen allow-list. It also inserts explicit `null` points across a gap so Chart.js
  **breaks** the line, because an interpolated line through missing data reads as a measurement
  that never happened.
- **Charts**: `climate_charts_controller.js` lazily `import()`s Chart.js (the cytoscape/leaflet
  pattern). Chart.js is an ES module, so there is no `window.Chart`. The controller exposes its
  instances as `element.climateCharts` plus a `data-climate-charts-ready` count, which is how the
  system tests assert the exact plotted values.
- **Which sensors are "the crypt" is stored, not inferred** (`Climate::Sensor#in_crypt`). `placement`
  separates indoor from outdoor, but a dressing-room sensor is indoor too and would poison a
  crypt-only worst case. Only ticked sensors feed the risk and ventilation charts; the raw history
  charts still show every active sensor.
- **The margin chart aggregates with `MIN(temperature_c - dew_point_c)` per row, then takes the
  worst of them.** NOT `MIN(temperature_c) - MAX(dew_point_c)`, which takes its two figures from
  different instants and invents a crypt that never existed, and not `AVG`, because a daily mean
  margin can sit at 5 °C while every night touched 1. `Climate::MarginSeries` has a test that
  fails under either wrong form.
- **`Climate::RiskSummary` counts against hours that HAVE readings**, never hours in the range: the
  sensors sync over an intermittent access point and routinely miss days, so "41 of 720 hours" reads
  as 6% of a month when it means 8% of the six days covered. A coverage gap also **breaks** a
  continuous spell, the same principle as not drawing a line across missing data.
- **`Climate::VentilationSeries`'s worst case is the single coldest crypt sensor**, resolved once
  from the lowest mean temperature over the range, not a composite of the lowest temperature and
  highest dew point across sensors. A chart whose two lines came from different sensors cannot be
  read for the gap between them, and that gap is the first thing anyone reads. It is a projection
  over `SeriesQuery`, not new SQL, so it aggregates with `AVG` deliberately: it is read for the
  present, and `MarginSeries` owns the historical worst case.
- **Bucketing and sensor colours live in `Climate::Buckets` and `Climate::SeriesColors`**, shared by
  all four chart payloads. A margin line bucketed differently from the temperature line above it
  would be unreadable next to it, and a sensor must be the same colour on every chart.
- **Shared Chart.js machinery is in `app/javascript/lib/climate_chart.js`.** Four chart controllers
  and `jscpd` gating at threshold 0 means the palette, the lazy import and the end-label plugin
  cannot be copied per controller.

## Pretix ticket widget

Inline on a show page (`shared/_pretix_widget`) and in the home page's Buy Tickets modal
(`shared/_pretix_modal` + `pretix_modal_controller.js`). All URLs come from `PretixHelper`.

- **The widget's script and stylesheet come from the shop domain, never pretix.eu** —
  `pretix.eu/widget/v1.en.css` 404s and the bundle injects no CSS of its own, so pointing there
  renders the widget unstyled. The shop origin must be in **both** `style-src` and
  `style-src-elem` (browsers enforce them separately for `<link>`); `content_security_policy_test`
  pins that.
- **Building a widget destroys its element**: pretix replaces `<pretix-widget>` with its own
  wrapper div, so `event` can only be set once. The modal creates a fresh element per open and
  calls `window.PretixWidget.buildWidgets()`, or every open after the first shows the first show.
- The modal `<dialog>` is a flex column (scoped to `[open]`, or it beats the UA's
  `dialog:not([open]) { display: none }`) so its header stays put as the widget grows.

## Box office display (Anthias)

Public unauthenticated pages under `/display` for the box office screen, plus `/display` itself,
which lists the playlist for whoever sets up the Pi. `Display::PagesController` resolves one panel
per URL through `Display::Chain`; panels live in `app/services/display/panels/`.

- **Anthias plays a fixed playlist of these URLs forever, unattended.** A page that renders nothing
  is not a blank page for a moment, it is a blank screen in the box office until somebody notices
  and reconfigures the Pi. `Chain` appends the query-less `Panels::Identity` itself so a chain
  cannot resolve to nothing, **the empty-database test in
  `test/functional/display/pages_controller_test.rb` is the feature**, and anything that can raise
  mid-render is rescued for the same reason (`display_image_url` returns nil on a blob missing from
  storage rather than 500ing the screen).
- **Blank `performance_weekdays` means every day of the run, and no duration rule may stand in for
  it.** A year-long Improverts event with no weekdays set is `on_today?` daily and prints
  "Sep 1 - Jun 30", the exact string `display_when` exists to avoid; a duration filter would instead
  drop a three-week Fringe run that genuinely is on every night.
- **The display layout must not load `application.css`** — its unlayered `h1`-`h6` rules beat the
  Tailwind utilities sizing this screen. `display.css` imports `tailwind-base.css` only and owns the
  two display-scoped tokens: `--color-display-accent` (`text-primary` is 2.9:1 on black) and
  `--leading-descender`, which every `truncate` here must be paired with or `overflow: hidden` slices
  the descenders flat.
- **The What's On board scrolls with pure CSS, and the scroll is self-limiting.** Show titles wrap
  instead of truncating, so the list can outgrow the frame; `.display-marquee` translates the track
  by `min(0px, calc(var(--display-marquee-viewport) - 100%))` — the `100%` is the track's own
  height, so a track that fits yields a positive distance and clamps to no movement at all. That is
  why the box takes an explicit `height` from that same variable rather than `flex-1`: the variable
  IS the box, so the two cannot drift. `100cqh` would say this directly and needs no constant, but
  Anthias's QtWebEngine predates container query units — the same engine that rendered the QR code
  as a blank square. **The `17.25rem` in that variable is the panel's header, footer and padding
  summed by hand**, which is why `_whats_on.html.erb` pins them (`h-18`, `h-9`) instead of letting
  content size them.
- **The marquee's pass is ONE fixed duration, so the speed varies with the distance.** That is the
  only pacing a fixed Anthias slot can take: constant speed would make a long board need a longer
  slot than a short one, and since the playlist holds a single number the slot would have to cover
  the worst case, leaving every ordinary board sitting there twice as long as it needed. The
  distance is the *overflow*, not the list — twelve short titles overflow by ~310px and twelve
  wrapping ones by ~1030px. Don't pace it per event: that had the common case crawling at 16px/s,
  near six seconds a row. A test asserts the slot still covers the pass, reading the duration out
  of `display.css`.
- **`Display::Panels::News`'s budget is in measured pixels, not guessed characters.** Every constant
  maps to one Tailwind class in `_news.html.erb` and was measured in Chrome; `CHARS_PER_LINE = 68`
  sits between the 76 characters a mixed-case headline fits and the 66 an all-caps one does. It was
  55, which charged the real top headline three lines for the two it renders as and stopped the
  slide after two items with 372px of black space under them. The list's `min-h-0 overflow-hidden`
  is the safety net under that arithmetic: a wrong answer clips a headline instead of pushing the QR
  code off screen.
- **Only the display self-hosts Source Sans Pro.** `theme.css` has always *named* it in
  `--font-sans` without anything loading it, so the rest of the site still renders in whatever
  `system-ui` resolves to. Any layout arithmetic done against rendered text is therefore only
  trustworthy on display pages — see `plans/off-topic-improvements.md`.
- **`OnThisDay` joins `image_attachment`** because `fetch_image` *attaches* a placeholder, so "has
  real artwork" must be asked of the database first. `eager_load` adds the preload alongside that
  join; on its own it outer-joins and silently drops the guard.
- **There are no curtain times in the schema.** An event carries dates, not performances, so nothing
  here can say "7.30pm" without a migration.
- **The archive slide moves on one place every time it is rendered** (`Display::Rotation`, a cached
  cursor keyed by date). Anthias comes back to that one URL every few minutes, so picking the oldest
  match every time showed a single frame from open to close. A cache that cannot answer falls back to
  a random pick rather than standing still.

### Deployment

On merge, set the Improverts event's `performance_weekdays` to Friday in the admin, and do the same
for any other intermittent long-running event — see the blank-weekdays trap above.

## Opportunities

An `Opportunity` is a posting (a "project"): it `belongs_to :company` (optional) and `has_many :roles` (`OpportunityRole`, a position + `category` enum). It carries `project`/`author`, `compensation_type`/`experience_level` enums, an `apply_url`, and `email_visibility`/`contact_email`. `title` is optional — `display_title` (and `to_label`) fall back to "Company: Project", enforced by the `has_display_title` validation.

- **Submission is public.** Anyone may submit via `GetInvolvedController#new/#create`; logged-out submitters provide `submitter_name`/`submitter_email` (creator is `nil` → `external?`), protected by a honeypot + reCAPTCHA. Members are attributed to their account; managers can pick a different creator on the admin form. A manager entering an external submitter there is recorded as the creator (`on_behalf_of?` — creator *and* submitter present); `attribution_label` renders all three cases. All submissions are `approved: false` until reviewed. `creator_or_submitter` requires one or the other.
- **Listing** (`get_involved#opportunities`): `Opportunity.listable` (the public set) + Ransack filters (company/compensation/experience) + a `?category=` tab, sorted EUTC-first. `active` = `listable` ordered internal-first. Per-society shareable links use `?q[company_slug_eq]=…`.
- **Display:** one `OpportunityCardComponent` renders the project + role sub-list for the public list and the home/dashboard widgets.
- **Review:** `Opportunity Reviewer` role; approve/reject email whoever actually submitted (`OpportunityMailer`, `notification_email` — the account creator when present, so on-behalf decisions go to the internal user, else the external submitter) with an optional note. Reviewers also get the `OpportunityDigestJob` digest. A `close` member action (aliased to `:update` in Ability) expires a posting immediately.
- `Company` (name + `acts_as_url` slug + `internal` EUTC flag) is admin-managed via `Admin::CompaniesController`.

# Testing
Start the test database using `docker start /mysql8` before running any tests.

- **The suite runs in parallel** (`parallelize` in `test_helper.rb`, capped at 8 workers —
  measured optimum on a 20-thread machine; past the physical cores the workers contend, and
  MySQL, shared behind the per-worker databases, is its own ceiling). `PARALLEL_WORKERS=1` to
  debug a failure serially. **System tests are pinned to 1 worker** in
  `application_system_test_case.rb`: in parallel they are flaky and no faster.
  Rails gives each worker its own *database only*, so any new **shared filesystem or process
  state needs splitting per worker** in `parallelize_setup` — the ActiveStorage disk root, the
  generator tests' `tmp/generators`, and SimpleCov's `command_name` already are. A teardown
  must remove `ActiveStorage::Blob.service.root`, never a hardcoded `tmp/storage`, which under
  parallelize is another worker's data.
- **Never put a dev-only gem in the `:test` group.** `better_errors` + `binding_of_caller` were
  there, and both bite: they attach a `Binding` to exceptions (unmarshalable, so every parallel
  failure became an unreportable worker crash), and `BetterErrors::Middleware` was silently
  sitting in the *test* middleware stack swallowing app-server exceptions, which left the system
  tests green over 8 real errors. If system tests suddenly surface server errors, that is them
  working, not breaking.
- **A slow suite is usually the machine, not the suite.** Same 3027 tests: 560s on the
  `power-saver` power profile, 116s on `performance`. Check `powerprofilesctl get` first; the
  tell is a local run losing to CI. Don't trust `/proc/cpuinfo` MHz, which reads ~500 MHz either
  way. See [plans/test-suite-speedup.md](plans/test-suite-speedup.md) for the full profile.
- **Minitest 6 made `load_plugins` opt-in**, so a `minitest/*_plugin.rb` on the load path
  silently never runs — require it and push onto `Minitest.extensions` yourself.

- **Validation/error messages are i18n-customised** (e.g. presence reads "must not be blank.", not Rails' default "can't be blank"). Assert on `errors[:field].present?` rather than the literal default string.
- **Admin search-form/index table headers** translate symbol headers via `t("simple_form.labels.defaults.<key>")` (see `SearchFormHelper` and `shared/_table.erb`). A new column used as a header or search field needs a matching key in `config/locales/simple_form.en.yml` under `simple_form.labels.defaults`, or the page raises "Translation missing".
- **The markdown editor (`Admin::MdEditorComponent`) cannot be driven by Playwright `fill`** — it syncs its contenteditable into the hidden description textarea on submit, overwriting injected values, so the form re-renders with a blank-description error. Cover any form with a description editor via request-level functional tests (`post :create`) rather than a browser submit; form rendering and other Stimulus interactions (e.g. the `nested-form` Add/Remove buttons) still verify fine in the browser.
- **Fixtures with an explicit `id:` break association-by-label references.** Some fixtures set an explicit `id:` (e.g. `test/fixtures/users.yml` `admin` has `id: 1`). Referencing such a record by label in another fixture's association (`creator: admin`) sets the foreign key to `ActiveRecord::FixtureSet.identify(:admin)` — a *hashed* id that does **not** equal the explicit `id`, so the loaded association (`opportunity.creator`) comes back `nil` even though `creator_id` is set. When a test relies on the association resolving, reference the explicit id directly (`creator_id: 1`), not the label.
- **Capybara's `select` can't drive most admin selects.** `select_controller.js` replaces every
  `.simple-select2` element with a **Tom Select** widget and hides the original `<select>`, so
  `select "X", from: "Label"` raises `ElementNotFound`. Click the widget instead (`.ts-control`,
  then the `.ts-dropdown-content .option`) — see `tom_select` in
  `test/system/admin/reimbursements/producer_js_test.rb`. Tom Select fires a native `change` on
  the underlying select, so Stimulus actions bound to it still run.
- **`test/system/konami_code_test.rb` errors with `ActiveStorage::FileNotFoundError`** on a
  seeded header image (verified on an unmodified `main`, 2026-07-28) — a pre-existing failure,
  not something your branch broke.
- **No mocking library:** the suite has neither mocha nor `minitest/mock` (minitest 6 dropped it). Don't write `.stubs`/`.stub`. Stub external services by toggling their config instead (e.g. force a reCAPTCHA failure with `Recaptcha.configuration.skip_verify_env.delete("test")` and no token in the request).