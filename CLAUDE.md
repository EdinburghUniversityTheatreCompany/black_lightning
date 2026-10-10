# Black Lightning - Claude Code Guidelines


## Packages
Rails 8.1, minitest, Tailwind v4 site-wide, Stimulus for all JavaScript sprinkles. Vite, not
jsbundling, cssbundling or importmaps; Propshaft serves some images and page-specific JavaScript.

**Use pnpm, never npm, yarn or bun.** Its version is pinned only in `package.json`'s
`packageManager` field and provided by corepack (the `corepack enable` `postinstall` on the node
tool in `mise/config.toml`; CI's `pnpm/action-setup` reads the same field, so give it no
`version:` pin). Bump it with
`corepack use pnpm@<version>`; never hand-edit the integrity hash.

## JavaScript
- Stimulus controllers go in `app/javascript/controllers`, custom modules in `app/javascript/lib`,
  stylesheets in `app/javascript/styles` (Vite).
- JavaScript used only on specific pages goes in `app/assets` (Propshaft).
- Third-party CSS/JS vendored verbatim (not ours, not for Tailwind/PostCSS) goes in
  `vendor/assets/{stylesheets,javascripts}`, not `app/assets`. Propshaft registers it and
  `.jscpd.json`'s `**/vendor/**` glob already excludes it, so it needs no per-file exclusion.
- **eslint lints only `app/javascript/controllers` and `app/javascript/lib`** (hk and CI alike), so
  `sweetalert/`, `setup/`, `helpers/` and the entrypoints are never linted.
- **Flash alerts are text, never HTML.** `FlashHelper#flash_as_alert_hash` sends plain strings and
  `sweetalert/alerts.js` shows them through `titleText` or text nodes, so markup in a flash prints
  literally. The `toast` stream action's `html` attribute is the only HTML opt-in. Never hand a
  string holding user text to SweetAlert's `title:` or `html:` (both parse HTML); use `titleText:` /
  `text:` or an element built with `textContent`.
- **A Tailwind class in SweetAlert's `customClass` loses to any property SweetAlert's own CSS sets**
  (`swalCustomTheme.scss` is unlayered, utilities are layered). Put the class on an inner element.
- **`data: { confirm: }` does nothing under Turbo.** Ask with `data: { turbo_confirm: }` (a
  `button_to` takes it as `form: { data: { turbo_confirm: } }`; `get_link` takes `confirm:`).
- **A Turbo-submitted form whose redirect lands on another layout loses its flash**: Turbo's fetch
  of the target uses it up, then the changed tracked assets force a reload. So sidebar Log Out,
  Cancel my account and `get_link`'s buttons on the public site (`LinkHelper#form_confirm_data`)
  confirm through `confirm_controller` (SweetAlert, then a native submit). `data: { turbo: false }`
  is no substitute: Turbo then never asks. `test/system/confirm_dialogs_test.rb` pins both kinds.
- **A table cell with its own background ignores `.table-hover`'s row grey** (a `bg-white` cell,
  or `.table-pinned-actions`' pinned cell, which wins on specificity). Give every cell of such a
  row `group-hover:bg-gray-50`, with `group` on the `<tr>`, or the row greys unevenly.

## Maintain Documentation

If you learn something other agents would need, add it to this file as the last item of your
to-do list.

## URL as state
Always keep GET state in the URL, with readable parameters where possible.

## Button Styling

`ButtonComponent` (`app/components/button_component.rb`) is the single source of truth for button
styles: a plain module of class strings that renders nothing (never `render ButtonComponent.new`).
**Never use Bootstrap `btn btn-*` classes**; the shims are gone. Variants: `:primary`,
`:secondary`, `:danger`, `:success`, `:warning`, `:info`, `:link`. Sizes: `:sm`, `:md` (default),
`:lg`. To change a colour or add a variant, edit only `ButtonComponent::VARIANT_CLASSES`.

### How to render a button

```erb
<%# Model resource links: get_link handles permissions and paths %>
<%= get_link(@user, :edit) %>
<%= get_link(@user, :show, variant: :primary) %>
<%# Custom target for nested routes %>
<%= get_link(Admin::Feedback, :new, link_text: "Submit Feedback", link_target: new_admin_show_feedback_path(@show)) %>
<%# Non-model links and form submits %>
<%= link_to "Import", new_admin_membership_import_path, class: btn_classes(:primary, :sm) %>
<%= f.submit "Save", class: btn_classes(:primary) %>
<%# Inside ViewComponent templates (components don't get helpers) %>
<%= f.submit "Save", class: ButtonComponent.classes_for(variant: :primary, size: :sm) %>
```

## Admin copy is written for a regular user of the screen

Admin prose costs space on every visit and is read by someone who uses the screen weekly. It earns
its place only by saying what the controls cannot:

- **Lead with what the reader can act on**, never with the format of the list below it.
- **State the consequence, not the mechanism.** "A bounce afterwards is invisible here", not "the
  portal hands the message to Microsoft".
- **Print a limitation only with what to do about it**, and print a knowable date or number
  ("before 2026-09-19", not "before this log existed").
- **Cut cross-references to other screens' matching quirks.**
- **Traps survive the cut, shorter.** Tighten a screen's trap wording; never delete it.
- **Producer-facing screens are the exception** (`expenses/**`, `reimbursements/emails/**`): a
  producer files a claim once or twice a term, so more explanation is right there.

## Admin forms

**One vocabulary for every admin form.** `FormStyles` (top of
`config/initializers/simple_form_tailwind.rb`) holds the control classes, read by simple_form's
wrappers and by hand-rolled `form_with url:` forms through `input_classes` / `file_input_classes`
/ `checkbox_classes` and `shared/form/_field`. Never type `border border-gray-300 rounded …` into a
view.

- **Model-backed forms use simple_form**: `simple_horizontal_form_for` + `shared/pages/form` for
  the older label-column layout, plain `simple_form_for` for the stacked finance layout.
- **Flat-param forms** (no model) wrap a `CardComponent` in `form_with` and put
  `render "shared/form/actions"` in `card.with_footer`. **The `form_with` must open outside the
  card**: the footer is a slot, so a form opened inside renders its submit button outside the
  `<form>` and the button does nothing. Only a browser test catches it.
- **A form whose POST answers by rendering a page must set `data: { turbo: false }`** (as
  `Admin::ImportFormComponent` and the climate import do). Turbo silently drops a 200 answer to a
  form submission. Inside a Turbo Frame a 200 is fine (so the reimbursements wizards need no
  opt-out). Only a browser test sees it.
- `shared/back_link` is the "← All …" line above a card; `shared/form/paste_or_upload` is the
  shared paste-box-plus-file-input pair.
- **`shared/form/field`'s `html_class` defaults to `mb-4`, and any class you pass replaces it.** In
  a `flex items-end` row a field with no width class of its own needs `html_class: ""`, or it sits
  16px above its neighbours.
- **simple_form renders any attribute named like `*email*` as `type="email"`**, which takes one
  address. A field holding several (`CostCentre#notification_email`) needs `as: :string`, or the
  browser refuses `a@x; b@y` and Save silently does nothing.
- **A select Tom Select takes over must carry only `simple-select2`.** Tom Select copies its
  classes onto `.ts-wrapper`, so a border there draws a box inside a box (simple_form's
  `CollectionSelectInput` strips them; a `select_tag` must not add them). The one border is
  Tom Select's `.ts-control`: never override it away.
- **A `multiple` Tom Select needs the empty hidden `name[]` field beside it** (Rails emits it for
  `collection_select … multiple: true`; a hand-rolled `select_tag` must add it), or removing the
  last choice posts no key and the old list survives.
- **A disabled fieldset does not disable a Tom Select** (it looks live while submitting nothing):
  call `tomselect.disable()` too.
- **Tom Select is built after an async `import()`**: listen for the `select:ready` event
  `select_controller` dispatches; never assume `el.tomselect` exists on connect.
- **Receipt add/remove on both expense edit pages answers only a turbo stream** replacing
  `#receipts-gallery` (`AttachesReceipts#respond_with_receipts_gallery`, `finance: true` on the
  finance routes); `receipts_upload_controller` is the only client. A plain HTML post makes its
  change, then raises `UnknownFormat`: 406 in development, the 500 page in production. Both render
  `admin/reimbursements/shared/_receipts_dropzone` inside the `receipts-upload` controller element.

## Link Helper

**Use `get_link` from `LinkHelper` for button-style links to model resources.** It picks the
`ButtonComponent` style from the action, checks CanCanCan permissions and builds the path.

## ViewComponents
Check for an applicable skill, and create a preview (a cop requires one).

- **The namespace says who renders it.** Top level = both sites (`ImageComponent`,
  `GalleryComponent`, `SearchFormComponent`, `CardComponent`); `Admin::` / `Public::` = only that
  site. A component both sites render must not carry either prefix.
- **`app/views/shared/` is not a home for reusable markup**; a reusable piece is a component. Only
  page scaffolding (`shared/pages/*`) and the form field vocabulary (`shared/form/*`) stay there,
  because they read controller ivars or wrap a form builder.
  Never create `app/views/admin/shared/`: two "shared" directories have had a component render a
  partial from the wrong one and 500 in production.
- **A `@admin_site` read in markup becomes a constructor argument** when the markup becomes a
  component (`GalleryComponent#show_tags`, `TeamCreditsComponent#admin_site`). A component must
  not reach for controller state.
- **Write `alt:` as a literal keyword at the `image_tag` call.** herb's `html-img-require-alt`
  cannot see an alt merged in from an options hash.
- **`MdEditorComponent` takes `layout:`**: `:horizontal` (admin default, label column) or
  `:vertical` for the three public forms (complaints, opportunity submission, profile completion).
  Only vertical styles the `<label>`. **`uploads:`** (default true) must be `user_signed_in?` on
  those three, as `MarkdownController#upload` needs sign-in. With `uploads: false` the editor
  offers no image button and swallows a dropped file.
- **Giving a form the markdown editor means adding the form object's class to
  `MarkdownController::ITEM_TYPES`**, or its image uploads answer 422. A record edited on its
  parent's form (an answer, question, category info, review) also needs a branch in
  `MarkdownController#can_save_form_of?`, or a user holding only the parent's permission gets 403.
- **Public-site form classes come from `bootstrap_compat.css`, which must shim the class
  simple_form actually emits.** Off the admin site `simple_horizontal_form_for` uses the bootstrap
  `horizontal_*` wrappers, emitting `col-form-label` and `form-text`. `form-group row`,
  `col-sm-3` and `col-sm-9` are deliberately not shimmed, so those forms stack.

## Dev Environment (mise + hk)

**mise config lives in `mise/`, not the repo root.** `mise/config.toml` (+ `mise/mise.lock`) pins
Ruby and Node and holds the tasks; `mise/config.development.toml` (+ `mise/mise.development.lock`)
adds `hk`, `pkl`, `gitleaks`, `zizmor`, `actionlint`, read only when `MISE_ENV=development`. The
committed `.miserc.toml` sets that (CI sets it explicitly); without it every commit fails with "No
version is set for shim: hk". Production never runs mise. A worktree's gitignored
`mise.local.toml` sits at the repo root and layers on top. Pre-commit runs through **hk** (`hk.pkl`; overcommit is gone):
run `mise install && hk install` once.

- **Ruby is precompiled** (`compile = false`, from jdx/ruby; glibc ≥ 2.17, bundles its own
  OpenSSL/libyaml/libffi). It is explicit so a global mise `compile` default cannot flip
  `mise/mise.lock`. The devcontainer still needs a C toolchain for native gems (bcrypt, mysql2,
  nio4r, puma, …). Builds exist only for `linux-x64`, `linux-arm64`, `macos-arm64`; `macos-x64`
  compiles from source.
- **Run all checks with `hk run check`** (CI mirrors its steps); autofix with `hk run fix`. **Plain
  `hk run check` scans only the working diff**, so verify a branch with
  `hk run check --from-ref <base> --to-ref HEAD`.
- **Never `git stash`.** `refs/stash` is shared by every worktree and live session, so
  `git stash pop` can take someone else's work. Use a throwaway commit and `git reset --soft`.
- **`HK_SKIP_HOOK=1` does not stop hk's repo-wide stash.** When another session may be working in
  the repo, commit with `--no-verify` and run the checks over the branch afterwards.
- **The Gemfile's `cooldown: 4` needs Bundler ≥ 4.0.13; older ones ignore it silently** (Ruby
  4.0.2's built-in Bundler is 4.0.6). Keep `BUNDLED WITH` at or above that
  (`bundle update --bundler=<version>`). It is working when an update lists
  held-back releases ("available in N days").
- **The pre-commit hook autocorrects, so tests green before `git commit` prove nothing after it.**
  When it reports `rubocop – N files modified`, re-run those tests. `Rails/OutputSafety` rewrites
  `"…".html_safe` into `safe_join(...)`, a view helper, which raises `NoMethodError` in a PORO.
  Where the string is safe by construction, keep `html_safe` and disable the cop on that line with
  the reason.
- **hk steps:** `rubocop` (+`rubocop-minitest`), `eslint`, `herb`, `annotate-models`, `brakeman`,
  `bundler-audit`, `fasterer`, `database_consistency`, `debride`/`flay`/`jscpd`, `gitleaks`,
  `actionlint` + `zizmor`, exec-bit and large-file guards, `versions`, and `bin/rails test`. The
  exec-bit and `versions` steps run the same `scripts/check_*.sh` as CI: change the script, not
  its two callers.
- **`annotate-models` is fix-only** (never a CI gate): committing a model or `db/schema.rb` runs
  `annotaterb models`, skipping when no DB is reachable. **It reads your dev database, so a pending
  migration strips real columns from models you never touched.** Run `bin/rails db:migrate` before
  committing after a pull; the tell is an unrelated model in `git diff --stat`.
- **Gate status** ([plans/off-topic-improvements.md](plans/off-topic-improvements.md)): `herb-lint`
  and `jscpd` (threshold 0) gate. `herb-analyze` is advisory (`|| true`) only for the two
  HTML-email fragment partials it cannot parse standalone. `database_consistency` is advisory
  (`|| true`): legacy integer-PK checkers are disabled in `.database_consistency.yml`; about 330
  findings remain, 76 of them missing length validators (mostly `reimbursements_*`), most others
  NOT NULL / FK / unique-index gaps needing data-aware backfill migrations. Two herb rules are
  disabled in `.herb.yml`.
- **Secrets:** `gitleaks` scans the tree, with gitignored secret paths allowlisted in
  `.gitleaks.toml`. Real plaintext secrets still sit in `config/` (move them to production
  credentials). The hk step scans only the working tree; the CI `gitleaks git` job scans full
  history. Reviewed dead findings are baselined by fingerprint in `.gitleaksignore`, each with a
  comment; any new secret still fails. Never rewrite history to purge them:
  all are dead, and it would re-SHA ~3900 commits.
- **Committed files over 512 KB fail** CI's `audit` job and hk's `check-added-large-files`.
  Flat-colour PNGs shrink with no visible loss as PNG8: `convert … PNG8:out.png && optipng -o5`.
- **The devcontainer is mise-driven.** [.devcontainer/Dockerfile.dev](.devcontainer/Dockerfile.dev)
  installs only `mise` plus OS libs; [.devcontainer/setup.sh](.devcontainer/setup.sh) runs
  `mise install`, and `mise/config.toml` / `mise/mise.lock` are the single source of truth for
  Ruby, Node and the dev tools. **Never pin a language version there** (no `ruby:x.y` base, no
  `apt-get install nodejs`): that reintroduces drift. When the toolchain or `DEV_ENV_VERSION` changes, native build deps go
  in `Dockerfile.dev`, bootstrap steps in `setup.sh`. The toolchain is cached on the `mise-data`
  volume.
- **Read [docs/production-host.md](docs/production-host.md) before running anything heavy on the
  production host.** 1.7 GB RAM, `fuse-overlayfs` Docker and a 44 GB disk: two heavy I/O jobs at
  once have taken the site down.

## Dev Server

- **Run with `mise run serve`** (`serve:app` Puma + `serve:assets` Vite; no `bin/dev`, no foreman).
  **Start one yourself when you need it** (screenshot, visual check); this overrides the global
  "ask the user first" default. Check the port first (`ss -ltn | grep ":${PORT:-3000}"`) and run it
  in the background.
- **A provisioned worktree has its own ports** (`PORT`, `VITE_RUBY_PORT` in its gitignored
  `mise.local.toml`; see `.worktree-isolate.conf`). Run `mise run serve` from the worktree, or you
  get a server on the wrong port against the wrong database.
- **Stop the dev server before `bin/rails test:system`**, or ~57 unrelated system tests fail, nowhere near the cause.
- **App code reloads per request; boot-time state needs `bin/restart-web`** (`config/initializers`,
  `config/*`, `Gemfile`, env vars, new or enum-backed columns). `touch tmp/restart.txt` does
  nothing here. It finds Puma by the checkout's directory name, so it never restarts another
  worktree's.
- **`vite.config` or JS dependency changes need a full restart**: `Ctrl-C` `mise run serve` and
  rerun it (or rerun the VS Code "Dev server" task).

## Background jobs (Solid Queue)

- **`config/recurring.yml` times are `config.time_zone` ("Edinburgh"), not the container clock**
  (Solid Queue ≥ 1.5 appends `SolidQueue.time_zone` to a schedule naming no zone). For clock time,
  set `config.solid_queue.time_zone = nil`.
- **Two recurring tasks due the same second deadlock, and Solid Queue drops one silently**
  (`RecurringTask#enqueue` rescues the `EnqueueError`: no retry, no failed-job row).
  - **Every daily schedule sits on its own minute, none divisible by 5**
    (`reimbursements_mailbox_poll` owns those). `recurring_schedule_test` enforces both.
  - `RecurringEnqueueRetry` (prepended in an initializer) retries a deadlocked enqueue up to three
    times with jittered backoff: a net under the staggering, not a substitute. It is safe because
    `RecurringExecution.record` writes both rows in one transaction and the unique
    `(task_key, run_at)` index catches an attempt that committed.
- **The queue schema is schema-loaded, not migrated** (`db/queue_schema.rb`,
  `migrations_paths: db/queue_migrate`). `bin/rails generate solid_queue:update` copies in new gem
  migrations (none as of 1.6.0; our schema matches the gem's tables).
- **Give each alert state its own error class.** An error built with `.new` and never raised has
  no backtrace, so Honeybadger groups it at the `ErrorReporting#log_and_notify` frame: two states
  sharing a class become one fault, and a notice joining an open fault notifies nobody.
- **A job test expecting a raise calls `.new.perform`, not `perform_now`** (as `BuildBatchJob`'s
  do): `ApplicationJob`'s `retry_on StandardError` turns a raise under `perform_now` into a
  re-enqueue.

## Database & Migrations

- **Multi-database app.** Use `bin/rails db:rollback:primary STEP=n` (namespaces `primary`,
  `queue`, `cache`); bare `db:rollback` errors.
- **After a failed MySQL migration, run `bin/rails db:migrate:status` before any rollback.** MySQL
  DDL auto-commits partway, so a blind `STEP=1` can revert an unrelated migration.
- **Legacy tables have integer primary keys** (`opportunities` and other older ones). A foreign key
  to one must be `t.references :parent, type: :integer` (or `t.integer`), or the FK migration
  aborts. New tables default to bigint.
- **The running dev server caches the schema at boot**: after adding columns it 500s (e.g.
  "Undeclared attribute type for enum ...") until `bin/restart-web`.
- **Drop a column one release after the release that adds it to `ignored_columns`.** Rails names
  every column on INSERT, so dropping in the same release breaks the outgoing container's writes
  while the new one boots. Once the drop has run, never `kamal rollback` past the ignoring release.
  Pending ([plans/off-topic-improvements.md](plans/off-topic-improvements.md)):
  `PaymentDetails`' `iban`/`bic`, `EusaActual`'s `source_month`, `Budget`'s
  `area_before_rollback`/`name_before_area_rename`.
- **A data migration that writes through a live model breaks on a later re-migrate** once that
  model validates a column newer than the migration. Write SQL, or guard the validation with
  `has_attribute?`.

## Models and controllers

- **Never gate an `after_commit` on `saved_change_to_x?`**: inside one transaction it sees only the
  last save's changes, so an earlier change to `x` is missed. `Event#clear_author_name_list` runs on
  every commit for this reason.
- **A virtual attribute on a nested-attributes child does not make the row dirty**, and autosave
  skips unchanged rows, so an edit to only that field is silently lost. Its writer must mark a real
  column changed (`OpportunityRole#department_name=` calls `department_id_will_change!`).
- **`.count` on a paginated relation counts only the page.** `X-Total-Count`
  (`GenericController`) reads Kaminari's `total_count`.
- **Rails 8.1's `rate_limit` raises `ActionController::TooManyRequests` by default**, which
  `ApplicationController`'s `rescue_from Exception` turns into a 500 page and a Honeybadger report
  in production: always pass a `with:` that renders 429 (as `MarkdownController` does). Its
  counters live in `Rails.cache`, one memory store per test process, so the action's test class
  clears it in setup.
- **A JSON endpoint a signed-in page calls must `skip_before_action :require_profile_completion!`**,
  or a user with an incomplete profile gets the completion page's HTML, and that page's own editor
  breaks.
- **A token lookup fed from params checks `token.is_a?(String)` first**: `find_by_token_for` and
  `find_signed` raise `NoMethodError` on `?token[]=x` (`User.find_by_profile_completion_token`).
  Changing a `generates_token_for`'s `expires_in` voids every outstanding token.
- **`ClientIpStripper` drops every Client-IP header**, ahead of `ActionDispatch::RemoteIp`. Never
  make it conditional on the caller: a Client-IP disagreeing with X-Forwarded-For makes `remote_ip`
  raise `IpSpoofAttackError` in `Rails::Rack::Logger`, outside `ShowExceptions`, so the visitor gets
  a bare 500. `test/integration/client_ip_header_test.rb` pins it.

## Schema annotations

`annotaterb` (config `.annotaterb.yml`; not the Rails-8-incompatible `annotate` gem) maintains models' `# == Schema Information` blocks;
`lib/tasks/annotate_rb.rake` re-runs it on `db:migrate` in development, or run
`bundle exec annotaterb models`. Only models are annotated
(`exclude_factories/fixtures/tests: true`). **Keep `:format_rdoc: false`**: RDoc output
re-appends its Foreign Keys section on every run. **The header leaves out a model's
`ignored_columns`** (their indexes stay listed), so ignoring a column changes it at once: update it
in the same commit, or the next commit touching any model rewrites it as an unrelated diff.

## Attachments: allowed file types

`Attachment::ALLOWED_CONTENT_TYPES` (`app/models/attachment.rb`) is the only upload allow-list
(no browser `accept` filter).

- **Every allow-listed type must be known to Marcel**, or `active_storage_validations` raises
  `ArgumentError`. Register missing ones in `config/initializers/sheet_music_mime_types.rb` and
  restart the server.
- **Register a zip- or xml-wrapped format (`.mscz`/`.mxl`/`.musicxml`) with the container as
  `parent:`**, so Marcel keeps the specific type. Never allow bare `application/zip` or
  `application/xml`: it lets any zip/xml through.

## Permissions

The grid discovers models via `ApplicationRecord.descendants` in
`Admin::PermissionsController#set_models_and_roles`. Add a child model managed only through its
parent (like `OpportunityRole`, `MarketingCreatives::CategoryInfo`) to the exclusion list there.

- **What a role may do is a grid permission; who someone is stays a role check.** Gate on
  `can?(:access, :committee)` / `can?(:review, :proposals)`, never `has_role?("Committee")`.
  `User#member?` / `User#committee?` (and `with_role(:member)`) are facts and must never be
  grantable from a grid checkbox: a stray tick would mass-mail that role and mint pretix
  memberships overnight. `member?` excludes life members, who count only for pretix discounts.
- **A miscellaneous-only grid subject must be a symbol (`proposals`), never a model name.** A grid
  save calls `update_permission` for every listed subject with only the actions the grid offers,
  deleting the other stored rows (such as the `manage` rows non-admins approve with).
- **A miscellaneous permission reads false until `set_permissions_based_on_grid` has run**, late in
  `Ability#initialize` for non-admins. Put derived rules next to the `:duplicate` /
  `:membership_import` ones.
- **Every role name referenced in code is in `Role::HARDCODED_NAMES`** (matched case-insensitively
  by `Role.hardcoded_name?`, as code asks for `:member` and `"Member"` alike). It blocks rename and delete only; archiving is unaffected.
- **A new permission replacing a role check needs a data migration** granting it to the roles that
  had the access (like the two `Grant…Permission` migrations of 2026-09-05) **and** matching
  fixture rows, since test and CI databases are schema-loaded.

## Reimbursements portal

Producer-facing expense portal under `/admin/reimbursements`
(`Admin::Reimbursements::BaseController < AdminController`), gated by the grid permission
`access`/`reimbursements` (a symbol subject like `:backend`, listed in
`Admin::PermissionsController`'s miscellaneous permissions), linked from the sidebar's Finance
category. Data is in the `reimbursements_*` MySQL tables (`Reimbursements::{Expense,Person,Budget,…}`,
receipts on ActiveStorage). Airtable is gone (no `REIMBURSEMENTS_BACKEND` switch, no
`Reimbursements::Airtable::*`); `airtable_record_id` columns are import provenance, never written.

- **`eusa_code` stays on `CostCentre`; never model EUSA codes as an entity.** If a centre's code
  ever differs by year, add a thin `financial_year_cost_centres` join (year x centre to
  `eusa_code`, plus per-year run-days and mailboxes if needed).
- **`/admin/reimbursements` is the front door for both audiences** (`HomeController#show`):
  finance gets the dashboard, anyone else is redirected to their own claims. The branch is in the
  action, not a before_action, so a producer never 403s there. `Reimbursements::FinanceHome`
  reads existing readers only and totals GROSS `amount`, never the ex-VAT rollup figure.
- **`Reimbursements::Glossary` is the one definition of every portal word.** Screens print
  subsets inline via `shared/_glossary_terms`; `.terms` raises on an unknown key. The page needs
  only the base portal permission, not finance: owners and producers read it too.
- **Claim status words for producers come from `ReimbursementsHelper::PRODUCER_STATUS`**: a label,
  a tooltip to the submitter, and a third tooltip wherever the second would be wrong about someone
  else's claim. A page about other people's claims (an area's claims table) passes
  `own_claim: false` to `reimbursements_producer_status_badge`. `ClaimTabs` labels its tabs from the
  same hash, so a claimant reads one word per status everywhere.
- **Each undo reverses exactly what its forward action wrote.** Ledger `unlink` also reverses the
  settlement (Paid + `payment_confirmed_date` from `settle_expense_from_actual!`) and refuses a
  From-EUSA claim the row created (it has no earlier state). `offset_pair` re-pairs two rows by
  hand with the detector's hard requirements, not its scoring. A budget update can be opened and
  removed as a unit; `delete_budget_update!` DESTROYS its forecasts (`dependent: :nullify` would
  leave them unlabelled). A rejected claim reopens to Pending, never Approved, so it re-enters the
  owner gate.
- **Every Notifier email is logged, one row per recipient** (`Reimbursements::NotificationLog`,
  written in `Notifier#send_email`, the single chokepoint; kind = template basename, so a new type
  logs itself). `record` swallows its own failures: an unlogged sent email beats a logged unsent
  one.
- **Notifier templates may call `*_url` helpers only because `Notifier#renderer` passes in the
  mailer's host and protocol** (`action_mailer.default_url_options`; a missing host raises). A bare
  `ApplicationController.render` outside a request answers `http://example.org`, so a render path
  that skips it ships dead links no relative-path assertion catches.
- **`CostCentre#contact_email` is never the receive mailbox**: email-in polls it and files a
  question as a receipt. It is the first notification address, else a send mailbox that is not the
  polled one, else nil, and producer emails then name no contact.
- **A producer email must never say "reply to this email".** `Notifier` sends from the centre's send
  mailbox and `GraphClient#send_mail` sets no reply-to, so where send and receive are one mailbox
  the reply is polled as email-in (answered "no usable receipt" and moved to the Rejected folder,
  or made a blank draft). Point the producer at `CostCentre#contact_email`, guarded by
  `if contact_email`.
- **The EUSA covering email's body is operator-editable raw HTML** ("Body (HTML)" on Build Batch,
  prefilled with the composed message). Plain text plus `{{placeholders}}` was tried and reverted
  (`ebd09724`): the table is for searching old email, and EUSA pays from the BACS spreadsheet.
  **The batch total, claim count and "receipts are also attached" line exist only in the opening
  paragraph of `emails/eusa.html.erb`**, so replacing it drops all three silently.
- **Everything goes through `Reimbursements.build_store`** (`Reimbursements::DatabaseStore`, the
  single gateway, frozen public API). Never hit AR models from controllers or jobs. No cache:
  lists are memoized per instance, one store per request or job run.
  `DatabaseStore::LastReceiptError` guards removing an expense's last receipt.
- **Budget figures and the overview** (`Reimbursements::Budget`, `NominalCodeRollup`,
  `/admin/reimbursements/budgets/overview`):
  - **`eusa_actual_amount` is linkage-based and net.** Expense budgets count actuals reconciled
    to their expenses, Income budgets those booked against their `budget_id`; never match on
    nominal code (budgets share codes). Both net through `EusaActual.net` (debits less credits,
    offsetting legs dropped), so a refund reduces a line.
  - **`DatabaseStore#unattributed_actuals` keeps unlinked spend visible** (overview's second
    card): rows linked to neither an expense nor a budget, offsetting legs excluded. Not "nominal
    code with no budget", which hid spend behind any budget sharing the code.
  - **Never total Expense and Income budgets together**; every total comes from
    `NominalCodeRollup#by_type`. **`expected_outturn` is nil for an Income budget** and blank
    everywhere (overview, index, edit, CSV, xlsx): its max would read as best-case income.
  - **`Budget#remaining` reads the plan (`projected_amount`)**, so a fresh import has figures;
    `variance` follows, £0.00 with no forecast. An Income line stays forecast-only (its plan is a
    target to raise). Nil only with no figure, printed "No budget set"
    (`reimbursements_budget_remaining`), never a dash.
  - **"Projected" is the one on-screen name for that figure** (`reimbursements_budget_projected`,
    `(initial)` with no forecast logged). Exports keep both columns and names: never rename or
    reorder an export column.
  - **Only `store.budgets_with_actuals` preloads actuals** (budgets index, overview, Budgets export
    sheet), not `store.budgets`. Don't switch a caller: the producer's budget `<select>` once
    loaded the whole ledger that way.
- **Areas** (`Reimbursements::Area`, `Admin::Reimbursements::AreasController`) group a show's
  budget lines under one agreed total and one owner set.
  - **The area owns, its budgets inherit.** `Budget#owners` resolves through the area, whose
    owners win. An area line's leftover `own_owners` rows are kept: they apply again if the line
    leaves its area.
  - **Owners are edited on the area, and every writer writes the table the gate reads.** The
    budget form shows an area-bound line's owners read-only and omits `owner_ids`; the importer
    sends its owner to the area, and `#owner_syncs` takes only lines with no area. Compare
    against the rows you write (`owner_ids` reads through the area, so never converges). A blank
    list is dangerous: `where.not(person_id: [])` is `WHERE 1=1`.
  - **The budget form refuses owners ticked for a line going into an area**, rather than writing
    them to `own_owners`, which `Budget#owners` stops reading once there is an area. The guard
    reads the area the form is giving (`#create`'s `Budget.new` has nil `area_id` until assigned).
    A Stimulus controller disables the fieldset once an area is chosen, so no `owner_ids` post and
    own-owner rows are left alone. A line already in an area offers no list; a stale post is
    ignored.
  - **An area naming nobody switches its budgets' sign-off gate off** (`OwnerReview
    .gate_applies?`), even for a budget with its own owner. Both forms warn.
  - **A budget shown on its own names its area** (`Budget#display_name`: `"Cogito: Marketing"`).
    Stored names repeat across shows, so a bare name in a picker charges another show and moves
    the claim to its owner gate. Pickers, reminders, emails, receipt filenames and the derived
    BACS reference read it; `active_budgets` is ordered by it. Bare only beside the area (grouped
    index heading, overview area card, an export's Area column, the form's name field).
    - **The separator is a colon, for correctness**: `BudgetImport.bare_name` splits on it, so a
      copied label resolves; a dash imports as a duplicate create. `FilenameSanitizer` turns the
      colon into a space (illegal on Windows and SharePoint), so `Cogito Props` still names the
      show.
  - **`Budget#picker_label` stays separate from `display_name`**, `<select>` collections only. It
    prefixes `CostCentre#picker_prefix` (`short_code`, else `eusa_code`) because `active_budgets`
    is not centre-scoped. On `display_name` it would change the BACS reference, receipt filenames
    and what `BudgetImport.bare_name` matches.
  - **`reject_if: :all_blank` cannot judge a row whose select has no blank option** (the nested
    row always posts `budget_type`, so an untouched row 500'd). `Area::UNTOUCHED_BUDGET_ROW`
    judges the fields the operator fills, and `AreasController#budget_row_error` must read the
    same lambda.
  - **A budget inherits its area's cost centre and financial year** (`before_validation`, blanks
    only, so a placed line never moves). An unstamped line is lenient-scoped into every year,
    centre and producer picker.
  - **The area `<select>` must always offer the budget's own area**: it comes from
    `areas_for_year` (scoped), `area_id` writes unscoped and `""` detaches, so Save would detach
    another year's area.
  - **A forecast belongs to exactly one of a budget or an area** (validation + MySQL CHECK,
    enforced on the pinned mysql:8.4). Area forecast = the show's agreed total; budget forecast =
    a line's allocation. It cannot be area-only: many lines (Contingency) have no area.
  - **A plan of exactly £0 counts as unset** (`Reimbursements::PlannedAmount#no_budget_set?`, in
    Budget and Area): nil, or zero with nothing allocated under it. Many termtime areas have £0 and
    real spend, and a cap of nothing would show them all over budget for ever. `remaining`,
    `variance`, `unallocated` and `over_budget?` go quiet on it.
  - **`remaining` and `unallocated` are nil, never zero, with no agreed total**; zero reads as
    fully overspent.
  - **Read area figures off `store.areas`** (unscoped, preloads `:forecasts` and
    `budgets: [:expenses, :forecasts]`; the area's own `:forecasts` because `Area#projected_amount`
    reads them), never `budget.area`, whose unloaded `budgets` N+1s.
  - **The grouped index's area subtotal covers the whole area**; its rows are scoped to year and
    centre, and the row says when fewer lines are shown than exist.
  - **The overview's area card totals the budgets the screen is scoped to** (`AreaRollup`), while
    "not yet allocated" covers every line ever linked to the area (a budget can hold another
    year's area). The heading's warning names only the allocation figure (the agreed total is the
    area's own forecast) and **states no direction**: an out-of-scope Expense line reduces it, an
    Income line raises it on `net` and leaves it alone on a spend cap.
  - **Area names are unique per (financial year, cost centre) by model validation**; a unique
    index cannot do it, since MySQL lets NULLs through and a new area may have NULL year and
    centre.
  - **`areas.budget_basis` declares what the agreed total is a total of** (`Area::BASIS_OPTIONS`
    and `#basis_label`, the same words on form and cards): `expenses` (a show's spend cap; income
    lines left out of `Area#allocated`) or `net` (a committee's allowance; income subtracted).
    Default `expenses`, no backfill: every existing area came from show-shaped lines, and a cap
    never overstates room.
    - **The basis governs only the agreed-total arithmetic.** `AreaRollup#by_type` keeps separate
      Expense and Income subtotals on both bases, which are never totalled together.
    - **`Area#remaining` deliberately ignores the basis**: `committed_amount` counts claims, and
      a claim on an income line is spend, not income; landed income is
      `Budget#eusa_actual_amount`, and committed and actual figures are never mixed (the edit
      card's `<dt>` `title` says so). A net area with landed income so reads lower than its real
      room (understating is the safe direction); fixing that needs a new named figure and a
      decision on EUSA credits (backlog: "`Area#remaining` understates a net-basis area whose income
      has landed").
    - **Print a netted allocation as two halves, never a bare negative** ("Allocated £400.00 of
      spend less £800.00 of income"), since a negative money figure reads as overspend here.
      Both the grouped index and the edit card use `reimbursements_area_allocation`.
    - **A rollback past `20260911100600` returns every area to a spend cap, recording nothing**
      (the `down` drops the column, the `up` re-adds it as `expenses`). Re-declare the net areas
      afterwards. It ships because it errs conservative (less room, never more). Backlog:
      plans/off-topic-improvements.md, "A rollback past `20260911100600` forgets every area's
      basis".
  - **The area backfill and prefix rename cannot be rolled back**: both migrations' `down`s raise
    `IrreversibleMigration`. `Budget` ignores `area_before_rollback` and `name_before_area_rename`
    until a later migration drops them; export the pre-rename names first
    (plans/off-topic-improvements.md, "Drop the two area rollback columns").
  - **`strong_migrations` blocks `add_reference … foreign_key:` on a populated table.** Use the
    gem's MySQL pattern: `add_reference`, then `add_foreign_key` inside `safety_assured` with
    `SET SESSION foreign_key_checks = 0/1`, `safety_assured` wrapping the `execute` calls too.

- **Financial years** (`Reimbursements::FinancialYear`, `Admin::Reimbursements::FinancialYearsController`).
  A year is built as a **draft** (create, import its budgets, check) and switched to with
  `activate!`, never a checkbox on the edit form: activating changes every submitter's budget
  picker. `activate!` stands the incumbent down and promotes the target in one transaction:
  `only_one_active` rejects a second active year, and a target that fails to save must never
  leave no active year.
  - **The selector is `?year=<key>`, on the budget screens only**
    (`FinanceController#resolve_financial_year!`; defaults to the active year, an unknown key
    alerts and falls back). Expenses, Review, Actuals, Batches and Reconcile are deliberately not year-scoped yet.
  - **`store.budgets` stays unscoped**: its callers are id→budget lookups (Review, the expenses
    index, exports, the nightly job) and the reconcile matcher, so scoping it blanks last year's
    budget names. The matcher reads every year, so a credit's code shared by this year's and last
    year's income line matches neither (see the credit-matching bullet under EUSA actuals).
    `budgets_for_year`, `budgets_with_actuals` and `budget_updates` are scoped.
    **`active_budgets` follows the active year, never the selected one**, so nobody files against
    a draft.
  - **A row with no year belongs to the year being viewed** (`DatabaseStore#in_year`), or an
    unstamped row (one older than financial years, or written while no year was active) would
    silently empty the budget list and every picker.
  - **In a test, restore the store seam with `BaseController::DEFAULT_STORE_BUILDER`, never
    `-> { build_store }`**, which drops the seam's `financial_year:` and `cost_centre:`; through
    `class_attribute` that sticks for the process, unscoping every later page in that worker. A
    fake that ignores scoping is `->(**) { fake }`.
- **Cost centres** (`Reimbursements::CostCentre`, `?cost_centre=<key>`): one pot's budgets,
  claims, ledger rows, batches and mailboxes. Selector: `FinanceController#resolve_cost_centre!`,
  rendered by `shared/_cost_centre_selector` on Budgets index and overview, Actuals, Review and
  Batch history.
  - **The sidebar carries these two selectors and nothing else**:
    `Admin::SidebarComponent::SCOPE_PARAMS` (`year`, `cost_centre`) is appended to every
    `scoped: true` finance item. The clash check parses the item's query string, never substring
    matches (`financial_year=` contains `year=`; `cost_centre_id=` is the same coordinate). A
    home-decorated item already carries `?cost_centre=`, so `item_href` joins the year onto that
    query, never a second `?`. Producer items are unscoped, as their own claims are.
  - **No `?cost_centre=` means every centre**, never `CostCentre.default`, which would empty the
    second centre's screens. `?cost_centre_id=<id>` still works (the import wizards' and budget
    form's selects post it); the key wins, so a create reading the form's choice reads
    `cost_centre_id` first (the form URL carries the page's centre).
  - **An empty `cost_centre=` is an explicit All, and it is carried**: the selector's All link sends
    it, `SidebarComponent` keeps it, and `FinanceController#scope_params` (what links and redirects
    carry: only what the URL named) keeps it, so the home centre does not come back on the next
    click.
    - **A finance link or redirect carries the scope with `**scope_params`, never
      `cost_centre: selected_cost_centre&.key`**, which is nil for an explicit All: the key drops
      and the sidebar puts the home centre back. Never run `compact_blank` over a hash holding
      `scope_params` (it strips the All's empty string); `ActualsController#actual_filters`
      merges them after it.
  - **A finance user's home cost centre (`users.reimbursements_cost_centre_id`) only decorates
    links**: the sidebar's day-to-day items while the page names no centre
    (`NavigationHelper#home_cost_centre_scope`, which also lets the sidebar's Build batch skip the
    chooser) and the import wizards' preselect. A bare URL still means every centre; never resolve
    it, redirect to it or default a store to it. `HomeCostCentresController` writes it with
    `update_column`, so no User validation can veto a preference.
  - **`hidden_from_submitters` filters `submittable_budgets`, the producer picker only.** Never
    apply it to `active_budgets`: Review, finance expense-edit and the actuals convert read that,
    and a hidden centre's claims must stay editable there. A line with no centre stays offered, and
    a producer's claim already on a hidden line keeps it (hidden means no new claims).
  - **`CostCentre.default` (`order(:id).first`) is an arbitrary pot once a second row exists.**
    Never use it where the answer is knowable (the claim's, the batch's, the selector's centre), or
    on a path that moves money or emails a producer. `.sole_configured` is the "nothing to choose"
    read.
  - **A read-only filter may be lenient; anything that moves money gives each claim exactly one
    centre.** `#in_cost_centre` puts an unplaced row in every centre. The money path reads
    `#expenses_owned_by_cost_centre` (unplaced falls to the default centre), because
    `BuildBatchJob`'s `limits_concurrency` key is per centre and a claim in two centres would reach
    two live EUSA drafts. `NightlyBatchJob` uses the same rule; `BatchProcessor#mark_submitted`
    re-reads and refuses a claim no longer Approved.
  - **Build Batch's centre travels in a hidden field, not the URL**: the form posts to a bare
    path, so a query string is lost. Only `build_batch_cost_centre_js_test.rb` sees it. With no
    centre selected, `new` renders a **chooser**; the centre is never inferred.
  - **Reopen probes a list of mailboxes** (derived centre, then default): older batches drafted
    into the default centre's, and `GraphClient#draft_message?` fails closed, so one wrong guess
    reads as "may already have been sent".
  - **A budget import adopts the unplaced line it matched** (`BudgetImport#adoptions`), or two
    committees share one row for ever.
  - **Centre-scoped readers:** `budgets_for_year`, `budgets_with_actuals`, `unattributed_actuals`,
    `expenses_for_cost_centre`, `eusa_actuals_for_cost_centre`, `batches_for_cost_centre`.
    **Unscoped by design:** `budgets`, `expenses`, `eusa_actuals`, `active_budgets` (lookups,
    Reconcile's pools, the picker). **`Exports::Workbook` uses a scoped reader for every sheet**,
    or the sheets stop adding up.
  - **Neither Expense nor Batch has a cost-centre column.** An expense resolves it through its
    budget, a batch through its expenses, so reopen reads the mailbox before the revert unlinks
    them. Review's tabs, counts and CSV come off one scoped list.
  - **Nominal codes are edited on the centre's Settings edit page** (`settings/_nominal_codes`,
    `Admin::Reimbursements::NominalCodesController` at `settings/:key/nominal_codes`: writes only,
    finance-gated).
    - **The section is a sibling of the centre's `simple_form`, never nested** (a nested form's
      submit does nothing). Each control is its own form; every write answers a turbo stream
      replacing `#nominal_codes` plus a `toast` (it carries the notice a redirect's flash would),
      so the centre's form is not re-rendered and a half-typed mailbox survives. Only a browser
      test sees this.
    - **The controller decides retire or delete**: a code on any budget line or EUSA actuals row
      is deactivated (leaves the pickers, still labels those rows); only an unreferenced one is
      deleted. The row's Retire/Delete label reads the same counts as `#in_use?`. A row with no
      centre counts in every centre.
    - **`code` is never updatable**: rows and exports store it as a string. The Settings
      `before_action` loading the section covers `update` too, as a refused save re-renders
      `:edit`.

- **Setting a year up = importing the committee's spreadsheet** (`Reimbursements::BudgetImport`,
  `Admin::Reimbursements::BudgetImportsController`, `DatabaseStore#import_budgets!`). Paste TSV or
  upload .xlsx (`ImportParsing`), preview, apply. **Stateless**: the input is normalised to
  canonical TSV (`BudgetImport#to_tsv`, escaping in-cell tabs and newlines) and carried in a hidden
  field, so apply re-parses and re-validates rather than trusting the preview.
  - **Only the preview's own TSV is unescaped, in both import wizards.** The preview renders a
    `canonical` hidden field that `ReadsImportSource#input_type` reads as `:canonical_tsv`;
    anything else is `:paste`, kept literal: unescaping a typed `Costume\next week` stores and
    matches a real newline (a revision becomes a create), and `C:\temp\report.pdf` is a path.
  - **Both coordinates are query params on one top-level route**
    (`/admin/reimbursements/budget_import?year=&cost_centre=`), never a path segment: years and
    centres are orthogonal. `?year=` is FinanceController's selector, so the store arrives
    year-scoped. Entry points prefill what they know (a financial year, the budgets
    index's year, a centre's settings page).
  - **The page `<h1>` must not name the year**: it is outside the wizard's Turbo Frame and goes
    stale. Each step's heading names its own.
  - **Buckets** per `(financial year, cost centre)`: create / revise / unchanged / invalid, plus
    `absent_budgets` (in the year, not the sheet), **reported, never deleted** (claims
    hang off them).
  - **A line matches on area plus bare name, and a stored line answers to both spellings**
    (`BudgetImport.bare_name`, `.area_scoped_key`, `#resolve_budget`): stored names lost their
    `Area: ` prefix but the sheet still sends it, and one spelling turns revisions into creates.
    Two stored lines answering one key **block, named**, never a silent pick.
  - **One exception (`#loose_match`): if several lines answer, the Area cell is blank and exactly
    one of them is in no area, that one matches.** It still blocks if the row named an area, the
    name is itself prefixed (`Cogito: Marketing`), or there are several loose lines or none.
    **A single answering line matches, loose or not**, deliberately: a bare row revises a show's
    only `Marketing`, or the committee's prefix-free sheet would be refused whole.
  - **A blank-Area row whose name carries the prefix of an area the sheet names keys as that
    area's row** (`#prefix_area_for`): `Cogito | Marketing` beside `(blank) | Cogito: Marketing` is
    one line twice. It normalises only the row's own key; several keys per row would make the
    duplicate relation asymmetric and non-transitive.
  - **A create adopts that area and is stored under the bare remainder** (`#area_name_for`,
    read by `#creates`, owner routing and the preview), or the next converted sheet creates it
    again in the area. `Budget#display_name` adds the prefix back, so a stored prefix renders
    twice. **A matched row keeps its Area cell as typed** (`#re_homes` and owner targets read it):
    a prefix is not enough to move a stored line.
  - **The preview states the line each row matched** (`Entry#matched_area_label`, `#matched_note`
    where the loose reading decided) wherever it differs from the typed cell. **An unmatched row
    says nothing**, or a first import claims every row matched a line in no area.
  - **The preview's Area column shows the area a row lands in** (`#area_name_for` again), marked
    `(from its name)` when read off the prefix: the operator's only chance to catch a wrong
    adoption.
  - **`#superseded_absent_budgets` links a create to the absent line** whose name is the create's
    area prefix plus its bare name. Nothing is merged; the link only lets the operator see the
    pair. The prefix must really be there, or it fires on the legitimate pair.
  - **Columns match strictly** (`StrictColumnMatching`, shared with `ExpenseImport`), never via
    `ImportParsing#find_column`'s "header contains keyword" fallback (it reads `Area Budget` as
    both name and area). Exact names, then multi-word substrings only; two fields on one column
    blocks, naming both; the preview states each field's column.
  - **Canonical headings: `Area total` and `Budget amount` are money, `Budget name` is the
    name.** Old `Area Budget` / `Budget` / `Amount` stay accepted. Each label `#to_tsv` writes must
    be in its own field's `exact` list, or the column vanishes on apply (a test pins it).
  - **`Area total` is the show's agreed total and repeats down an area's rows; two values for one
    area block.** Written only on create; a later, different figure is reported and logged as an
    area forecast (`#area_revisions`) under the same `BudgetUpdate`, compared
    against `Area#projected_amount` so re-imports converge. Trap: `Area`'s uniqueness check folds
    accents (`utf8mb4_unicode_ci`) and `match_key` does not, so `Cógito` beside `Cogito` must be
    refused in the preview, not 500 the apply and lose the paste.
  - **A budget's `initial_budget` is written only on create**; re-imports log forecasts under one
    `BudgetUpdate`, so `Budget#variance` stays drift from the agreed figure.
  - **The owner column names the area for an area-bound line, and area owners are the union**
    (`#area_owner_syncs`, never subtracting). `own_owners` on an area-bound line reaches no
    sign-off gate, so only a loose line takes that write. One stale address gains sign-off over a
    whole show, so the preview lists each area's owners by name.
  - **A different area for a stored line is a re-home, reported, never applied on sight**:
    checkboxes keyed by budget id (survives reordering). All unticked creates no target area
    (`#area_creates_for`).
  - **Submit is disabled when nothing will happen, so `#apply_work` must cover every bucket**
    (keyed by the `import_budgets!` argument doing each; a test asserts it), or a bucket such as an
    owner-only re-send cannot be applied.
  - **An unreadable amount blocks the whole import; an unknown owner email only warns**: a
    misread figure is silent wrong money, a missing owner shows as an unendorsed claim. Never
    auto-create a `Person` from a bare email. `import_budgets!` is all-or-nothing, unlike
    Reconcile's per-row rescue; re-running is cheap as matching is by name.
  - **Budget-import test sheets derive `HEADERS` from `TSV_HEADERS` and pad rows with the leading
    area cells**: a hand-written row shifts when a column is added, and `bin/rails test` skips
    system tests.
- **Importing settled claims** (`Reimbursements::ExpenseImport`,
  `Admin::Reimbursements::ExpenseImportsController`, `DatabaseStore#import_expenses!`). Same
  wizard and coordinates as the budget import, from the finance expenses index. All-or-nothing:
  an unreadable amount, unknown payee or budget, or bad status stops the lot, naming the rows.
  - **`Status` is mandatory and never guessed**; blank or unrecognised blocks. Approved enters
    Build Batch and emails its producer, Paid never does.
  - **The `ID` column (`Reference` still accepted) is the double-apply guard**: written to
    `expenses.import_key` behind a unique index, since a claim has no natural key and a second
    click re-posts. The preview's "already imported" bucket is a pre-flight read; when stale, the
    index holds and the rescued `RecordNotUnique` re-renders the preview.
  - **IDs are compared downcased** to match the `utf8mb4_unicode_ci` index (else `OLD-1` and
    `old-1` preview as two creates and the apply rolls back). Accents are deliberately not folded:
    over-matching would silently drop a new claim.
  - **A blank Submitter email means none given, never a lookup** (all email-less payees index
    under `""`). Then the `Submitter` name is matched (case, spacing, accents folded); a shared
    name blocks the row. It is "Submitter", not "Payee", because `Payee name` is an Invoice's
    supplier.
  - **Every rule comes from `ExpenseForm`; the model has none** (`Expense.create!({})` passes).
    The importer sets `internal` as `from_actual` does, plus **`settled`** (Submitted, Paid or
    Rejected rows), which suppresses `invoice_without_payee?` and `international_without_payee?`
    and nothing else: those guard the money path (`EffectivePayee` falls back to the submitter's
    own details), which only Approved claims enter.
  - **Rows with an `Expense number` are inserted first.** `auto_number` is unique;
    `create_expense!` gives a numberless row MAX+1 and never retries a collision on a number it
    was handed (data corruption).
  - **Columns match strictly via `FIELDS`**: the fields are near-anagrams, and the substring
    fallback read "Payment reference" as the dedupe key and "Account number" as the expense number.
    The preview stating each field's column is the only way to see a mis-mapping. Sheets built from
    `TSV_HEADERS` cannot catch this; the realistic-heading tests can.
  - **The import emails nobody, but what it writes decides what happens next**: producer email
    comes only from `BatchProcessor`, `NightlyBatchJob` or an explicit reject, so an Approved row
    goes on the next BACS spreadsheet (EUSA pays it again) and emails its payee; a Pending one is
    named to its budget owners nightly. Preview and apply count the non-terminal rows and say so;
    never reword that into "nothing was emailed".
- **Both import wizards refuse to guess the cost centre** (`ReadsImportSource#cost_centre_chosen?`
  / `#chosen_cost_centre`); never preselect `selectable_cost_centres.first`. Preview and apply
  re-render step 1 with the paste intact. With one centre configured nothing is asked;
  `?cost_centre=` / `?cost_centre_id=` prefills, else the operator's own home centre.
- **A grouped `<select>` needs `as: :grouped_select`.** A plain `collection:` with
  `group_method:` renders one option per group: it looks right and selects nothing. Assert the
  `<optgroup>` markup, not the controller's ivar.
- **A link inside a wizard's Turbo Frame needs `data: { turbo_frame: "_top" }`** unless the
  destination has the same frame, or the wizard becomes "Content missing". `shared/back_link`
  takes a `turbo_frame:` local and `shared/form/actions` a `cancel_turbo_frame:` one
  (`import_wizard_frames_js_test.rb` clicks every way out). Only a browser test sees it.

- **Typed money goes through `Reimbursements::AmountParser`** (`£1,200`, `12,50` comma decimal).
  `.parse` gives nil for anything unreadable; **`.parse!` tells blank (nil) from unreadable
  (raises)**, so the batch budget-update form never reads a typo as a deliberate skip.
  **`AmountValidation`** (Review#save, expense-edit #update) uses the same parser and adds: positive,
  within `MAX_AMOUNT` (100k), excl-VAT not above gross. Callers write the parsed
  `AmountValidation.amount` / `.amount_excl_vat`, never the raw param: AR casts "£1,200" with `to_d`
  and stores **0**.
- **Secrets** (`Reimbursements::Settings`): `REIMBURSEMENTS_*` ENV, then credentials
  `reimbursements:`. Real values live only in production credentials (development's are public), so
  Graph/Azure is unconfigured in development by design.
- **Outbound Graph calls are gated to production** (`Settings.outbound_enabled?`), elsewhere only
  with `REIMBURSEMENTS_ENABLE_OUTBOUND` (`test_helper.rb` sets it; the transport is faked). Without
  it a dev shell with real Azure credentials would email producers and PUT the BACS spreadsheet into
  production SharePoint. So email-in does nothing locally, by design: `MailboxPollJob#perform`
  returns at once, `send_mail`/`create_draft` log and return a stub,
  `Graph::MailboxClient#reply/#move/#mark_read` no-op. `upload_to_folder` and `delete_message`
  **raise** `OutboundSuppressedError`: a plausible return would stamp `receipts_offloaded` (telling
  a producer to delete their only copy) on receipts never backed up. Read-only probes stay live,
  so a centre's Settings "Run access check" works in dev.
- **Bank details are encrypted at rest** (non-deterministic, so never query them by value):
  `sort_code`/`account_number`/`notes` on `Reimbursements::PaymentDetails`;
  `sort_code_override`/`account_number_override`/`payee_name_override`/`iban_override`/
  `bic_override` on `Reimbursements::Expense`. Keys: production credentials under
  `active_record_encryption:`; development reads `REIMBURSEMENTS_AR_ENCRYPTION_*`, falling back to
  throwaway literals in `config/environments/development.rb` (a write needs a key even when blank);
  test uses literals in `config/environments/test.rb`. `development.key` is committed, so real key
  material must never go in `development.yml.enc`.
  - **`support_unencrypted_data = false`**, so stray plaintext raises. **There is no rollback**:
    removing `encrypts` makes the data unreadable; losing the production keys loses it outright.
    Production was backfilled 2026-07-26 with 0 failures; the all-rows sweep in
    [docs/reimbursements/encryption-rollout.md](docs/reimbursements/encryption-rollout.md) has not
    yet been run in its working form.
  - **A brand-new column with no plaintext rows needs only `encrypts` and a deploy** (as the
    IBAN/BIC overrides did). **An existing column holding plaintext repeats the whole sequence**:
    add `encrypts`, flag true, deploy, `reimbursements:encrypt_backfill`, verify, flag false,
    deploy. The backfill must read plaintext, so cannot run with the flag false, and aborts
    non-zero on any failed row, since flipping the flag over an unconverted row makes it unreadable.
  - **Rotating keys means appending to `primary_key`, never replacing it.** Rails encrypts with the
    last key and decrypts with any; replacing it, or changing `key_derivation_salt`, makes every
    stored value unreadable.
  - `config.active_record.encryption.validate_column_size = false`: it measures the decrypted value,
    so caught nothing real and crashed `database_consistency`. Plaintext length caps on the models
    do the job. Ciphertext is about 2× plaintext plus envelope, hence `payee_name_override` is TEXT.
- **The submission form validates the budget against the ids the controller RENDERED**
  (`ExpenseForm`, `offerable_budget_ids` from `active_budgets`): finance may delete a budget (FK 500,
  claim lost) or deactivate it (retired line charged) while a form is open. A **draft** is exempt:
  `update_attrs` drops the stale id and saves, since refusing costs the producer their typing over a
  field they may leave blank. `DatabaseStore::BudgetGoneError` covers a delete between
  validation and insert. The finance **expense-edit** form keeps existence-only
  `budget_record_id_error`, as it offers the inactive budget a claim is already on.
- **An Invoice claim must carry the third-party payee trio** (`ExpenseForm#invoice_without_payee?`):
  with blank overrides `EffectivePayee` falls back to the submitter's bank details, `ReviewSupport`'s
  "no bank details" check passes, and the producer is paid for the supplier's bill. Submit-time only
  (drafts and email-in save incomplete); the message points a self-paid bill to Reimbursement. **The
  finance edit form applies it too** (`ExpenseEditsController#expense_type_error`), but only while
  `ReviewSupport.attention_actionable?` (Draft/Pending/Approved), so Submitted and Paid claims stay
  re-typable without inventing bank details for a supplier never captured. That form is the only
  place `expense_type` changes after submission, and the only one offering From EUSA.
- **Review has three tabs; `to_approve` is the default** (`ReviewController::TABS`). Awaiting owner
  holds claims with an unmet owner gate; To approve's Ready / Needs attention split means a data
  problem only. An unrecognised `?tab=` falls back to `to_approve`; `pending` is aliased to it. The
  owner-gate lookup sits in `#index`, not `#load_queue` (HTML-only), because the CSV follows the
  tab. A claim with no budget or an ownerless one skips Awaiting owner
  (`OwnerReview.gate_applies?` is false). That tab renders the full card (finance override) and has
  **no bulk toolbar**: bulk approve skips every gated claim.
- **`:base` errors are rendered by `shared/pages/_form`**, not simple_form (`f.error_notification`
  is only the banner). A form not using that partial must render them itself, or an
  `errors.add(:base, …)` fails the submit with no stated reason.
- **No AI in this portal, by decision (removed 2026-07-31); do not reintroduce it casually.** Its
  disclosure told producers their receipts, and suppliers' printed bank details, went to Google's
  free tier, where Google may keep and read them. Gone: `Reimbursements::Extractor`, `AiChecker`/
  `AiCheckJob`, `PromptSafety`, `ruby_llm`, `gemini_api_key`, the four `ai_*` columns. **The VAT
  soft-block in `ExpenseForm` stays soft**, triggered only by ex-VAT not being below the total.
- **The nightly job reminds, it never gates** (`Reimbursements::NightlyBatchJob`): it submits nothing
  and builds no batch (Build Batch is operator-initiated). Per due run-day it sends stale
  **Pending**, the whole **Approved** queue, and one **owner sign-off** reminder per budget owner.
  `ReviewSupport.needs_attention` claims are listed in the approved reminder with reasons, never
  held back. Nothing to say counts as delivered.
  - **Job and `ReviewController` both split Pending on `OwnerReview.unmet_gate_expense_ids`**, so
    email and tabs agree. Gated claims go to owners (`remind_budget_owners`, `Person#email`,
    `GreetingName`), not finance.
  - **The owner reminder has no age threshold** (unlike `PENDING_REMINDER_DAYS`), names a claim
    every run-day until endorsed or rejected, goes to **all** its owners (any one may endorse, so
    telling one strands the claim while they are away), and skips an owner with no email.
  - **The owner reminder is best effort, outside the `.all?`** gating `record_nightly_run!`, so one
    dead owner address cannot withhold the run-day and re-send finance's reminders. Failures are
    reported (`reimbursements.owner_reminder_failed`); the claim stays on Awaiting owner either way.
  - **`record_nightly_run!` runs only when every finance reminder sent**, from one call site: it
    marks the run-day handled forever (`nightly_due?`) and nothing retries, so a half-sent run is
    retried whole (duplicates over silence). `deliver_reminders` collects results in an array and
    calls `.all?` so all are attempted; never rewrite it as a short-circuiting expression.
  - **It writes with `update_column`, not `update!`**, so no unrelated validation can veto the stamp
    (`notification_email` presence made `update!` raise for a blank-address centre). The job decides
    what counts as delivered; the model must not refuse to record it.
  - **Operator recipients are the cost centre's `notification_email`**, not the finance permission
    (which still gates every finance screen globally). `REIMBURSEMENTS_OPERATOR_EMAIL` is
    whole-portal and overrides it. Several addresses split on `;` or `,`, each format-validated.
  - **No recipients does not record the run-day**: it warns, fires the
    `reimbursements.nightly_no_recipients` Honeybadger event and retries tomorrow; Integration
    Status badges it.
  - **A claim whose budget names no cost centre goes to the DEFAULT centre**
    (`expenses_owned_by_cost_centre`, Build Batch's rule), never to nobody: a wrong recipient is
    visible and correctable, no recipient leaves a producer waiting. Build Batch's emails stay
    clicker-only.
  - **Never make the second cost centre a fixture**: `CostCentre.default` (`order(:id).first`) would
    depend on `FixtureSet.identify` hashing, and the reconcile tests pin a one-centre world. Use
    `create_reimbursements_cost_centre`.
- **Email-in**: `Reimbursements::MailboxPollJob` (every 5 min) polls the shared mailbox via
  `Graph::MailboxClient` (Graph app-only). Each inbound receipt becomes a **blank DRAFT** (subject
  as description) plus a "complete it in the portal" reply. Reply-then-move is the commit point;
  unread means it will retry.
  - **The app holds no Entra mail permission**: Exchange grants named mailboxes through RBAC for
    Applications, and the "Reimbursements App Access" group gates nothing. Authorise a mailbox by
    re-running `docs/graph-mailbox-rbac.ps1` with the **full** list from `bin/rails graph:mailboxes`:
    the scope is replaced, not appended, so a short list cuts off a working cost centre.
  - `CredentialsCheckJob` (daily) and `AuthError` alerts warn `alert_email` (IT subcommittee) before
    and when the Entra client secret dies. Keep the secret under `reimbursements:`: `Graph::Settings`
    reads `graph:` first, but `Reimbursements::GraphClient` and the expiry warning do not.
  - **`GraphAuth::AccessDeniedError` (a 403) subclasses `AuthError`**, so every rescue and the IT
    alert still catch it. Only Settings' access check tells them apart: scope or grant advice for a
    403, client-secret advice for any other `AuthError`, the bare message for everything else.
- **Producer emails greet by first name through `Reimbursements::GreetingName.for`**, shared by the
  `Notifier`'s ERB templates (rejection, producer_notification) and `MailboxPollJob`'s heredoc
  replies, so they cannot drift: linked `User#first_name`, then
  the first word of `Person#name`, then `"there"` (`PersonLink` may store an email as the name).
  Callers pass `greeting_name:`, keeping the Notifier ActiveRecord-free; `payee_name:` in
  operator-alert rows and the BACS payee stay full names. Heredocs must escape it with `ERB::Util`
  (`first_name` is self-service). `unknown_sender_html`/`rate_limited_html` say a bare "Hi," on
  purpose (no matched person).
- **Tests**: seed rows with the `create_reimbursements_*` helpers
  (`test/support/reimbursements_test_helpers.rb`). A pure-logic test builds an unpersisted AR model
  and pins DB-computed readers per instance (`define_singleton_method(:record_id) { … }`,
  `instance_variable_set(:@receipts, …)`, `build_payment_details`). External services are faked
  (FakeHttp, FakeGraphClient) through `class_attribute` builder seams on
  `Reimbursements::BaseController` and the jobs; no webmock. Never name a helper `message` (it
  collides with Minitest's `message(msg, ending)`). Strip real `REIMBURSEMENTS_*` vars from your
  shell before running the suite. Build a two-cost-centre world with
  `create_second_reimbursements_cost_centre`, never a fixture row and never inline (`jscpd` gates at
  0).
- **A claim with no bank details never reaches a batch** (`BatchProcessor#process` pre-flight
  `fail_with`, naming the claims). The approve blocker covers only the approval path, and the
  settled-claim import or a console fix reaches Approved without it; `bacs_document` would then write
  blank payee and account cells. It fails the **whole** batch: a spreadsheet quietly short of what
  was approved is harder to notice.
- **`ReviewSupport.modulus_result` is the one rule for when the modulus check applies** (attention
  summary and both banner views). The checker returns **INVALID for a blank pair**, which would
  print "likely a typo" under "no bank details". `FakeModulusChecker` must answer INVALID for a
  blank pair too, or tests cannot see this.
- **BACS batch invariants** (`Reimbursements::BatchProcessor`):
  - `lib/reimbursements/templates/EUSA_BACS_template.xlsx` caps a batch at `BacsXlsx::MAX_ROWS`
    (200), the range its GRAND TOTAL and the Authorisation Form's total cover; a bigger batch raises
    `TemplateError` rather than corrupting the total.
  - Both xlsx builders write through `Reimbursements::XlsxTemplate#write` (`change_contents`;
    `add_cell` drops the template's styling).
  - The Authorisation Form's centre name and budget holder come from the centre's Settings
    (`authoriser_name`, `authoriser_designation`; blank when unset). `BacsXlsx#generate` writes
    all three cells every time, so the template's own values never reach the workbook.
  - **`BuildBatchJob` raises on an unreadable BACS date or a missing attempt, never falls back to
    today**, and marks an existing `BatchAttempt` failed first, or History shows the build running
    until it goes stale (30 min).
  - `result.success` means every expense reached `Submitted`, not just that the draft exists. A
    `mark_submitted` failure is the one post-draft step that is not best effort: it leaves the
    double-draft danger the orphan-draft guard prevents.
  - `BatchesController#reopen` reverts or deletes a batch only when Graph positively confirms its
    draft is unsent; a draft already sent by hand must never be rebuilt into a second submission.

- **Exports** (`app/services/reimbursements/exports/`): one exporter per resource (`Expenses`,
  `Actuals`, `Budgets`, `Areas`, `Forecasts`, `People`, `Batches`) under `Exports::Base`, each
  defining `HEADERS` and a private `#row` once. That drives both the per-view "Download CSV"
  (`FinanceController#send_export` from each index's `format.csv`, linked as
  `request.query_parameters.merge(format: :csv)` so filters carry through) and the workbook sheet
  (`Exports::Workbook`, `ExportsController#download`). **Add a column in the exporter, never in a
  controller.**
  - **`GET /admin/reimbursements/export` is a page** (sheets, row counts in scope, year and centre
    selectors); `#download` is a separate action, not `?format=xlsx`, so no global MIME
    registration. The workbook opens with an "About this export" cover sheet (date, year, centre,
    sheets), so the file states its own scope.
  - Amounts numeric (no "£"); dates ISO 8601 strings, blanks empty (not "-"). **Every cell goes
    through `Reimbursements::CellSanitizer`** (the formula-injection guard `BacsXlsx` shares).
    `Base#add_sheet` pins String cells to Axlsx `:string`, or `041000` becomes 41000.
  - **Cost centre and area columns are appended** (area after centre), so saved formulas keep their columns. `People`
    has neither; `Batches` has no Area (a batch spans shows, so one cell would be a lie).
  - **Bank details in an export are masked to the last four digits** (`BankDetails.mask`, also the
    People notes audit line). Only the BACS spreadsheet carries full numbers.
- **Receipts are served by the app, never over ActiveStorage's routes**
  (`Admin::Reimbursements::ReceiptFilesController`): those are unauthenticated and permanent, and
  a receipt can carry a home address. So `Attachment#attachment_id` is the **blob id, never the
  signed id** (a bearer token for those routes; it must never reach markup); `remove_receipt!`
  matches on it. Streamed, not redirected (same-origin `<img>`/`<iframe>` under the CSP; Chrome's
  PDF viewer wants byte ranges), cached `private`. Visible to finance, the submitter and the
  budget's owners; anyone else gets 404, not 403.
- **Every uploaded receipt gets its own SharePoint name**: claim number plus an index
  (`<date> <budget> - <desc> #417 (2).pdf`, `FilenameSanitizer.build_receipt_filename`). Graph's
  `:/name:/content` PUT replaces a file of the same name, while `receipts_offloaded` tells the
  producer their copy is backed up, so a shared name loses a receipt silently.
- **`ReceiptIntake` strips metadata from raster receipts by re-encoding in the same format**, not
  by excising EXIF: location also hides in XMP, MakerNotes and the thumbnail. PDFs pass through
  untouched. A file merely named as an image (Marcel falls back to the filename) must decode or
  is rejected.
- **Bank details are cleared after six months without a claim**
  (`Reimbursements::BankDetailsRetention`, nightly). **`TERMINAL_STATUSES` lists the terminal
  set, on purpose**: an unrecognised status counts as live and blocks clearing, since wiping
  details about to be paid has no undo. Deleting a `User` destroys the payee's `PaymentDetails`
  (`User#erase_reimbursements_bank_details`, stored link then email); Person and claims stay
  (financial records).
  Preview a rule change with `reimbursements:bank_details_retention_preview`; no rake task runs
  the sweep.
- **On-screen bank details are masked until revealed**
  (`Admin::Reimbursements::BankDetailsComponent`: the UK pair or, with `iban:`, an international
  claim's IBAN; the BIC shows in full). Disclosure, not access control: the full value is in the
  markup, and everyone on those screens may see it. The People registry's editable fields hold real
  values as `type="password"` toggled to text, or someone saves `****4958` as an account number.
- **Finance registers a payee from a user account and collects no bank details**
  (`PeopleController#new/#create`): a budget owner may never claim (`BudgetOwner` needs no user),
  so "Unverified, no modulus badge" is correct. Don't add a bank-details step. It checks
  `person_for` first (an existing match is reported, not duplicated), then
  `PersonLink#ensure_person!`. `BudgetImport` still never creates a Person from a bare email; its
  preview links to this form.
- **Reconcile emails nobody, by decision: never wire a notification onto Paid.** EUSA's actuals
  land weeks after the BACS run, so a "you've been paid" note arrived after the money was spent.
  A producer's only payment email is `producer_notification`, when the claim enters a batch.
  (`Notifier#payment_confirmation` and its template are gone.)
- **EUSA actuals: offsetting pairs and conversion.** `Reconciliation.detect_offsetting_pairs`
  finds accrual/reversal legs in a paste. **Prefer missing a pair over inventing one**: a false
  positive hides real spend from the ledger and every rollup; a false negative just leaves rows
  unmatched.
  - **A credit links to an income budget only when exactly one income line in its cost centre
    carries its nominal code** (`Reconciliation.match_credit_to_budget`, candidates from
    `.credit_budget_candidates`, any year). With several, the row is saved unlinked and the preview
    says how many share the code; finance places it with Split across budgets. Never go back to
    first match: budgets share codes.
  - **Hard gates**: same absolute amount (exact BigDecimal), opposite sign, same nominal code,
    same cost centre, same financial year; a blank code or centre never pairs. Survivors score
    (ref 4, nominal 2, period 1, narrative prefix 1, minus 1 or 2 for date distance), taken
    greedily, floor `OFFSET_MIN_SCORE` 4. Nominal is a gate because a Sage payment-run ref spans
    a whole run and would pair a cost with unrelated income; ref and date cannot be (refs match
    half the time, legs straddle months).
  - **The EUSA period is two digits, zero-padded** (`Reconciliation.normalise_period`: parser and
    `EusaActual`'s `before_validation`). Sage writes it unpadded; only purely numeric values up to
    two digits change. **`actuals_for_period` normalises both sides**, or a re-paste
    double-counts a row written around the model.
  - **The ledger opens on `?state=needs_attention`** (`EusaActual#needs_attention?`, the predicate
    `DatabaseStore#unattributed_actuals` reads, so ledger and overview agree). `include_offsets`
    without `state` means the full ledger.
  - **Each pair is a ticked checkbox keyed by row content plus an occurrence index** (content alone
    merges byte-identical pairs; a row index breaks when rows shift). An unmatched key reads as
    unticked. Each pair says what unticking would pay.
  - **Both legs are written in one transaction** (`DatabaseStore#create_offsetting_pair!`,
    `reconciliation_status: "offset"` + `offset_of_id`): a half pair leaves the debit as spend,
    and dedup stops a re-paste fixing it. Rows are never deleted (audit trail); undo with the finance-gated
    "Not offsetting" button (`ActualsController#unoffset`, `DatabaseStore#unlink_offsetting_pair!`).
  - **Pairing by hand applies the same five gates and no scoring** (`EusaActual#offset_candidates`):
    a person is choosing, so an extra row costs a glance. The centre gate lives in the model, not
    the picker's source: the "Mark as offsetting" link carries no centre, so `#confirm_offset`
    re-checks through the same method. Unlike the detector, two centre-less rows may pair (rows
    predating cost centres count as belonging everywhere).
  - **An offsetting leg is never convertible to an expense** (`EusaActual#convertible_to_expense?`):
    it would invent spend. An unlinked debit converts (`ExpenseForm.from_actual`,
    `ActualsController#new_expense/#create_expense`) straight to Paid with the row's
    `payment_confirmed_date`, skipping review and batches.
  - **Conversion goes through `DatabaseStore#create_expense_for_actual!`**: create and link in one
    transaction, convertibility re-checked under a row lock, or a double submit double-counts the
    charge. `NotConvertibleError` redirects saying nothing was created twice.
  - `from_actual` sets `internal`, which admits `TYPE_FROM_EUSA` and relaxes the
    receipt/VAT/large-amount blocks. **Never make it a permitted producer-form param**, or a
    submitter dodges the receipt rule.
- **Income apportionment** splits one credit across income budgets:
  `reimbursements_actual_allocations` `(eusa_actual_id, budget_id, amount)`, written and undone by
  `DatabaseStore#apportion_actual!` / `#remove_apportionment!`, screen
  `ActualsController#apportion`. One Stripe payout covers a Fringe week; a row holds one `budget_id`.
  - **Credit rows only.** Split a debit by converting it into several expenses (debit budgets total
    through expenses, which allocations never reach). Offsetting legs are refused: they net to
    zero, so splitting one invents income.
  - **Apportioning is refused on a row with a `budget_id`** (`EusaActual#apportionable?`), or its
    full value would count on that line as well as its shares.
  - **`unattributed_actuals` must exclude apportioned rows explicitly**: its usual filter rejects
    rows that have a `budget_id` and an apportioned row has none, so each would sit on the
    overview's unlinked-spend card as a permanent false alarm.
  - **Parts must sum to `EusaActual#apportionable_total`** (credits less debits, as `EusaActual.net`
    derives it), **never the stored `net` column**, which is parsed separately and can be blank or
    disagree. A short split is refused whole, in one transaction, re-checked under a row lock.
  - **Two preloads or a page N+1s**: `:actual_allocations` on `budgets_with_actuals` and on the
    budgets in `DatabaseStore#areas`; `:allocations` behind `eusa_actuals`.
  - **The picker is unscoped**, like `store.budgets`: a credit in a year's tail often belongs to
    the year it was raised in. Active income lines only; posted ids are checked against the ids
    rendered.
  - `EusaActual#allocation_summary` feeds both the ledger badge and the export's Budget cell. A
    split row's export Area cell is blank on purpose (shares can sit in different areas).
  - **Expected income is a forecast on the Income line, never a pseudo-actual**: only an EUSA
    credit says money arrived, and an early figure that disagrees must then be resolved.
  - **Income is not an expense type** (asked twice, rejected): no payee, receipt or approval path.
  - **Stripe's fee is out of scope.** The payout is already net; a fee cost would be its own
    expense line against a fees budget.

### International payments

`expenses.payment_method` (`uk_bacs` / `international`) picks the rail. EUSA's international form
takes one payment, so a batch emits one BACS spreadsheet for UK claims plus one `InternationalXlsx`
form per international claim, all on the same draft.

- **`payment_method` is the discriminator, not the currency**: a supplier may invoice in GBP and
  still need an IBAN. `amount`/`amount_excl_vat` stay GBP, so rollups are untouched;
  `foreign_amount` + `foreign_currency` hold the invoice figure.
- **Currency comes from the fixed `Expense::FOREIGN_CURRENCIES`** (default EUR): a mistyped code
  is a payment EUSA's bank cannot route. The form has its own PAYMENT CURRENCY field.
- **After re-vendoring EUSA's template, check every `InternationalXlsx` cell constant against its
  A1 reference.** A revision can shift rows (2026-09-07's did), and a wrong constant silently
  writes the nominal code into the cost-centre cell. The amount cell's "£" stays for GBP; other
  currencies get a plain number format.
- **The submitter enters the invoice amount; finance types the GBP equivalent at review.** A blank
  `amount` blocks approval, checked BEFORE the ex-VAT guard or the wrong message shows.
- **`effective_has_bank_details?` is rail-aware and gates approval** (IBAN+BIC for international;
  modulus check skipped, not failed). `approve_blocker` and `ReviewSupport` share the predicates.
- **Every finance surface must read the rail's own fields; missing one fails silently** (the
  expense-edit override rule and `reimbursements_effective_modulus_badge` both once read the UK
  trio).
- **An international claim's ex-VAT amount mirrors its gross** (`before_validation`): no
  reclaimable UK VAT.
- **The template caches formula values; clear them.** The cache held EUSA's sample answers and
  named the wrong authoriser. `force_recalculation` sets `fullCalcOnLoad` AND drops the cache,
  since LibreOffice ignores the flag.
  - Authorisation rows 19-20 are left to `fullCalcOnLoad` (the thresholds are EUSA's to change),
    so they fill in Excel and render blank in LibreOffice. Open question for EUSA: do they
    populate when EUSA opens the form? One sample settles it.
  - EUSA's authorisation formulas use GBP thresholds (999.99 / 1,000 / 10,000) whatever the
    currency. Their template, not ours to fix.
  - Leave the `\x80` bytes in the `SET UP IN CASH FLOW` / `DESIGNATION` labels: EUSA's own mojibake.
- **No UK claims, no BACS spreadsheet**: an empty one asks EUSA to pay nobody. The covering email
  states each row in its own currency; the total stays GBP.
- **International claims reconcile on a percentage window**
  (`Reconciliation::INTERNATIONAL_TOLERANCE_RATE`, 5%): the stored `amount` is an estimate and
  the bank adds an FX spread. UK keeps the penny (wider only risks a wrong link). The matcher walks expenses, which know their
  rail; actuals rows don't.
- **Settle through `DatabaseStore#settle_expense_from_actual!`** (reconcile apply and "Link to
  claim"): marks Paid and corrects an international amount to what EUSA charged. **A UK amount is
  never overwritten**: it is what the producer spent. It re-reads the claim under a row lock and
  raises `NotSettleableError` for Draft, Rejected, or a Paid claim a payment date or another ledger
  row already settled.
  - **Reconcile and Link to claim disagree about Paid, on purpose.** Reconcile's
    `matchable_expenses` matches a Paid claim with no payment date and no linked row (an imported
    settled claim waiting for its EUSA row); Link to claim never offers Paid. `#settleable?` refuses
    only what neither should reach, so never tighten it to "never Paid" unless Reconcile's pool
    changes in the same commit.
- **An international claim's IBAN and BIC come only from its own overrides**
  (`EffectivePayee#effective_iban` / `#effective_bic`): a payee's People record holds no IBAN, so
  a screen must send finance to the claim's override.
- **A hidden input with HTML `required` silently blocks the whole form.** `required:` follows the
  active rail at render time and the Stimulus controller moves it (`data-rail-required`) on change.
  **`input_html: { required: false }` does NOT suppress it**: simple_form's own `required:` option
  wins, so pass that (`f.input :x, required: false`).

## Crypt climate monitor

Temperature, humidity and dew point charts at `/admin/climate`
(`Admin::Climate::BaseController < AdminController`), gated by the `climate` grid permission
(`read` to view, `manage` to configure sensors and import). Runbook:
[docs/climate/csv-import.md](docs/climate/csv-import.md).

- **Crypt readings arrive by CSV import; never reintroduce polling the Govee API.** It has no
  history endpoint and the crypt's WiFi drops out: the sensor's buffer, in the export, holds what a
  poller would miss. The dressing-room access point changes none of this; the link still drops.
- **`Climate::CsvImport` refuses a file whose header unit it cannot identify**
  (`Temperature_Celsius` / `_Fahrenheit`, following the app's display setting): the only defence
  against storing Fahrenheit as Celsius.
- **`Climate::ReadingIngest.upsert_series!` is the only write path** (manual import, mailbox job,
  outdoor poller). It owns the plausibility guard (-20..50 °C, 0..100 %), the dew point and the
  idempotent `upsert_all`; overlapping re-imports are harmless. Import is one step, not a preview
  wizard: no per-row decisions, and a 2-year backfill is too big for a hidden-field round trip.
- **Email ingest**: `Climate::MailboxPollJob` (every 15 min) reads CSV attachments from
  `CLIMATE_MAILBOX` over Graph (ActionMailbox is not installed and M365 has no inbound webhook).
  A file goes to the sole **active** Govee sensor (a deactivated, replaced unit is ignored). Two or
  more active, or only inactive ones, leave it unread with a once-a-day Honeybadger alert (one
  class and cache key per state); never guessed.
- **Graph plumbing is shared**: `GraphAuth`, `Graph::MailboxClient`, `Graph::Settings` (reads
  `GRAPH_*`, falling back to `REIMBURSEMENTS_AZURE_*`: one Entra app for the org, and renaming would
  break existing credentials). Reimbursements uses `Graph::MailboxClient` directly and rescues
  `GraphAuth::*` errors.
- **Outdoor data is Open-Meteo, which self-heals**: `OutdoorPollJob` upserts a rolling `past_days`
  window hourly, so an outage fills its own gap. Its CC BY 4.0 attribution must stay on the
  dashboard; the free tier is non-commercial only. A replacement source (Met Office, METAR) is a
  client answering `#hourly_series`, built by `OutdoorPollJob.client_builder`. The job polls by
  source (`Sensor.open_meteo`), never by placement, so an outdoor Govee sensor gets no Open-Meteo
  readings.
  - A failed poll reaches Honeybadger only after `OutdoorPollJob::REPORT_FAILURE_AFTER` (a day)
    without readings, since the next poll re-serves the window. Every failure is still logged and
    written to `last_error` for the staleness badge (`Sensor::STALE_AFTER`, 3h). Never having had a
    reading counts as missing.
- **The outdoor sensor row is ensured by `Climate::Sensor.outdoor_source!`, not a data
  migration**, because test and CI databases are schema-loaded.
- **`Climate::SeriesQuery` must not bucket with `UNIX_TIMESTAMP`**: mysql2 does not pin the session
  `time_zone`, so buckets shift by the server's offset. Use `TIME_TO_SEC(TIME(recorded_at)) % n`
  off a frozen allow-list. Explicit `null` points across a gap make Chart.js break the line: an
  interpolated line reads as a measurement that never happened.
- **Charts**: `climate_charts_controller.js` lazily `import()`s Chart.js (an ES module, so no
  `window.Chart`). It exposes `element.climateCharts` and a `data-climate-charts-ready` count,
  which system tests use to assert plotted values.
- **"In the crypt" is stored, not inferred** (`Climate::Sensor#in_crypt`): `placement` only
  separates indoor from outdoor, and a dressing-room sensor would poison a crypt-only worst case.
  Only ticked sensors feed the risk and ventilation charts; the history charts show every active
  sensor.
- **The margin chart takes `MIN(temperature_c - dew_point_c)` per row, then the worst of those.**
  Never `MIN(temperature_c) - MAX(dew_point_c)` (two different instants) or `AVG` (a 5 °C daily mean
  hides nights at 1). `Climate::MarginSeries` has a test that fails under either.
- **`Climate::RiskSummary` counts against hours that have readings**, never hours in the range
  (sensors miss days). A coverage gap breaks a continuous spell.
- **`Climate::VentilationSeries` uses the single coldest crypt sensor** (lowest mean temperature
  over the range), never a composite across sensors, or the gap between its lines means nothing. It
  uses `AVG` over `SeriesQuery` on purpose: it is read for the present; `MarginSeries` owns the
  worst case.
- **Shared by all four charts**: bucketing and sensor colours in `Climate::Buckets` /
  `Climate::SeriesColors` (one bucketing and one colour per sensor on every chart); Chart.js
  palette, lazy import and end-label plugin in `app/javascript/lib/climate_chart.js` (`jscpd`
  forbids copies).

## Pretix ticket widget

Inline on a show page (`shared/_pretix_widget` + `pretix_widget_controller.js`) and in the home
page's Buy Tickets modal (`shared/_pretix_modal` + `pretix_modal_controller.js`), both building
through `javascript/lib/pretix.js`. All URLs come from `PretixHelper`.

- **Never leave building to pretix's own bootstrap, so the script is not a `<script>` tag.** It
  builds every `<pretix-widget>` once and watches nothing, which under Turbo hits the outgoing page
  and never re-runs. `lib/pretix.js` loads the script, switches the self-build off through
  `pretixWidgetCallback`, and calls `buildWidgets()` once the element is in place.
- **Readiness is `window.PretixWidget.buildWidgets`, not `window.PretixWidget`**: the object is
  assigned early and the builder last, so a script that throws halfway leaves a useless object.
- **Building destroys the element** (pretix swaps `<pretix-widget>` for its own div, so `event` is
  set once). Both surfaces render an empty container and drop in a fresh element per build, or the
  modal keeps the first show clicked and a Turbo restore serves a dead widget.
- **Each build leaks** (pretix keeps every widget, with no teardown), so the controller skips
  Turbo's cached preview (`data-turbo-preview`).
- **The widget stylesheet comes from the shop domain, never pretix.eu**
  (`pretix.eu/widget/v1.en.css` 404s and the bundle injects no CSS). The shop origin must be in both
  `style-src` and `style-src-elem` (enforced separately for `<link>`);
  `content_security_policy_test` pins it. `widget/v1.*` and `widget/v2.*` are byte-identical on our
  shop, so "upgrade to v2" fixes nothing.
- The modal `<dialog>` is a flex column scoped to `[open]` (otherwise it beats the UA's
  `dialog:not([open]) { display: none }`), so its header stays put as the widget grows.

## Pretix membership sync

Member ticket prices are gated behind a pretix membership, driven from the `member` / `life member`
roles by `Pretix::MembershipSync`. Full detail in
[docs/pretix/membership-sync.md](docs/pretix/membership-sync.md).

- **A membership is validated against the show's date, not the purchase date**, so `date_end` caps
  how far ahead a member can book. Cohorts ending 31 Aug blocked every autumn show; no short
  rolling window works either.
- **The nightly `ReconcileMembershipsJob` is what makes this correct**; login, import and archive
  triggers only make it immediate. Never replace it with callbacks: `Role#archive` removes members
  with `users.clear` (`delete_all`, no association callbacks), so the annual de-membering needs its
  explicit enqueue.
- **Never read memberships from one whole-shop list; read per customer.** pretix pages them with no
  unique tiebreaker or `ordering` parameter, so `LIMIT`/`OFFSET` repeats and drops rows, and a
  dropped member would get a new membership minted every night.
- **The SSO identity claim is `email`, not `sub`; switching it locks every member out of the shop,
  unrecoverably** (every `identifier` re-hashes and logins die on the duplicate email; anonymising
  to free the email severs every order from its owner). Read the doc first.
- **Lookups resolve by `users.pretix_customer_identifier` first, email second.** The link is
  written only on the email path, so a stale one re-points and a working one is never disturbed
  (people with two pretix accounts would flip-flop otherwise).
- **Memberships cannot be deleted and customers cannot be pre-created.** Revoke with
  `PATCH date_end`. Creating a customer over the API breaks that member's next SSO login ("email
  address is already used for a different account").
- **Writes are gated to production** (`Pretix::Settings.writes_enabled?`): one organizer, no
  staging copy, so a dev machine would expire real members.

## Box office display (Anthias)

Public unauthenticated pages under `/display` for the box office screen; `/display` itself lists
the playlist for whoever sets up the Pi. `Display::PagesController#render_chain` shows the first
panel with content; panels live in `app/services/display/panels/`.

- **Anthias plays these URLs forever, unattended, so a page must never render nothing**: that is a
  blank box office screen until someone reconfigures the Pi. `render_chain` falls back to the
  query-less `Panels::Identity`; **the empty-database test in
  `test/functional/display/pages_controller_test.rb` is the feature**; anything that can raise
  mid-render is rescued (`display_image_url` returns nil for a blob missing from storage).
- **Run dates decide what is on the board, not the performance list.** `Display::EventPool` filters
  on `end_date` alone, so a show whose producer entered only the first week stays up for the
  second. `on_today?` still needs positive evidence, so such an event gets no "TONIGHT" flash.
- **An event with no `EventOccurrence` rows plays every day of its run; no duration rule may stand
  in for that.** Every archive event behaves so, and a duration filter would drop a three-week
  Fringe run that is on every night.
- **The display layout must not load `application.css`**: its unlayered `h1`-`h6` rules beat the
  Tailwind utilities. `display.css` imports `tailwind-base.css` only and owns two tokens:
  `--color-display-accent` (`text-primary` is 2.9:1 on black) and `--leading-descender`, which
  every `truncate` here must carry or `overflow: hidden` slices the descenders.
- **The What's On board scrolls in pure CSS and stays still when the list fits.** Titles wrap
  rather than truncate, so the list can outgrow the frame. `.display-marquee` translates by
  `min(0px, calc(var(--display-marquee-viewport) - 100%))` (`100%` is the track's own height), and
  the box takes its `height` from the same variable (not `flex-1`) so the two cannot drift.
  No `100cqh`: Anthias's QtWebEngine lacks container query units. **The `17.25rem` in the variable
  is the header, footer and padding summed by hand**, so `_whats_on.html.erb` pins them (`h-18`,
  `h-9`).
- **The marquee pass is one fixed duration, so speed varies with the overflow**: the playlist has
  one slot length. Never pace it per event. A test asserts the slot covers the duration in
  `display.css`.
- **`Display::Panels::News` budgets in pixels measured in Chrome**, each constant mapping to one
  Tailwind class in `_news.html.erb` (`CHARS_PER_LINE = 68`, between mixed-case 76 and all-caps 66).
  The list's `min-h-0 overflow-hidden` clips a headline rather than push the QR code off screen.
- **The font is self-hosted Source Sans 3 (from `theme.css`), never Source Sans Pro**, which has no
  weight 500 and so renders every `font-medium` at 400. Metrics match, so the measurements hold.
- **`OnThisDay` filters on the blob's filename (`Event.with_uploaded_image`), not on having an
  attachment** (never `joins(:image_attachment)`): `fetch_image` attaches a placeholder (under
  `ActiveStorageHelper::PREFIX`) to any event whose page was opened. `eager_load` must sit beside
  that join, never replace it: alone it outer-joins and drops the guard.
- **Curtain times come from `EventOccurrence` only when entered.** `display_when` prints
  "Fri 2 Oct, 7.30pm" from `Event::Schedule`'s blocks, else the bare date range.
- **The archive slide advances one place per render** (`Display::Rotation`, a cached cursor keyed
  by date), or Anthias shows one frame all day. A cache that cannot answer falls back to a random
  pick.
- **The credits QR always resolves**: `Event#digital_programme_url` when set, else the event's own
  page; the caption names which.
- **`display_credits_layout` picks side by side (Cast against Company) or flowed (one sequence down
  both columns), whichever prints names bigger, ties to side by side.** No lopsidedness threshold is
  needed: flowing only wins where a column was going to waste. It sizes in measured pixels, not rows
  (the QR is a different fraction of a row at each size). Side by side puts the QR under the shorter
  list and caps each list's height so a wrapping name clips the list, not the code; flowed makes the
  QR a footer. Re-measure `CREDITS_*` if the header, row spacing or QR size changes.

## Event ticket prices

`events.ticket_prices` is a JSON array of `Event::TicketPrice` bands (standard / concession /
member / other), with `booking_fee` beside it. Much of the archive has no bands, only the legacy
free-text `price`.

- **`price` stays the display string every view renders.** Admin edits to the bands regenerate it
  (`derive_price_from_ticket_prices`); clearing the bands clears only a price they wrote, never a
  hand-typed one.
- `ticket_prices` is not an association, so `shared/form/sections/_nested_fields` needs
  `template_object:` to build its add-row template.

## Team members

`TeamMember#display_order` orders the credits on every show, proposal and the box office
screen (`TeamMember.ordered`, nulls last then by name). Spec: issue #167.

- **The order is the row's position in the submitted form, stamped on save by
  `TeamMemberOrdering`** (`team_members_attributes=` on `Event` and `Proposal`). Browsers post in
  document order, so there is no hidden order field and the sortable controller renumbers nothing.
  `_destroy` rows are skipped (no gaps); blank template rows stay blank so `reject_if: :all_blank`
  drops them. Test it in an integration test, not a functional one (see **Testing**).
- **Listing one person twice on a show or proposal is a form error**
  (`TeamMember#uniqueness_in_parent_collection`, read off the loaded collection, new parents
  included). A new STI record's `type_changed?` is always true, so the type-conversion guard checks
  `persisted?` first.
- **The form renders through `TeamMember.in_display_order`, the in-memory twin of `ordered`, never
  the scope**: after a failed save a scope would render the stale rows instead of the submitted ones
  with their errors. Its name tiebreak folds accents (`transliterate`) to match
  `utf8mb4_unicode_ci`, or the form and public page disagree and the next save makes the form's
  order permanent. A test pins the two together.

## Event performances

`EventOccurrence` is one dated instance of an `Event`, nested-attribute edited on the admin event
form. It replaced the `performance_weekdays` column.

- **One table for Shows, Workshops and Seasons; only the word differs.** `OCCURRENCE_LABEL` per STI
  subclass ("Performance" / "Session" / "Opening time"), read through `Event#occurrence_label`.
  Never type the word into a view.
- **No occurrences means every day of the run.** `on_today?`, `next_occurrence` and `display_when`
  all branch on that; change one, change all three.
- `event_occurrences.event_id` is **`:integer`**, matching `events`' legacy primary key.
- **`Event::Schedule` reads the performances back as a shape**: `:range` (consecutive days, one
  curtain time), `:weekly`, `:single`, `:irregular`, `:none`.
  - **Blocks group by curtain time first, then fold by consecutive date**, or a Saturday matinee
    cuts the evening run into three.
  - **`:weekly`**: same weekday and time, gaps a multiple of 7, at least 3 dates spanning over a
    fortnight ("Every Friday, 7.30pm" instead of "Sep 4 – Jun 30").
  - **A run states the whole run**, so `display_when` is date-independent. Two stretches (an evening
    run plus late shows or a matinee) are both stated, a line each; folding them into one span would
    claim a midnight show every night. Past `DisplayHelper::WHEN_MAX_BLOCKS` (2) only the block
    covering today is shown, the one date-dependent case.
  - **The board collapses; the event page does not.** `Event::Schedule`'s blocks drive
    `display_when` only. `events/_performances` lists one row per occurrence with its badges inline,
  so nobody cross-references a range against a separate list of flagged dates.
- **The board's when-column does not `truncate`**: the longest value needs ~700px at `text-4xl`, and
  widening to that would eat the title, so it wraps like the title and the marquee scrolls the
  overflow.
- **The board renders `display_price`, not `Event#price`**: structured bands collapse to "£10/8/7"
  to fit the fixed 256px column.

### Deployment

On merge, add the Improverts' Friday dates (and any other intermittent long-running event's) as
`EventOccurrence`s in the admin. `performance_weekdays` was dropped with no backfill, so until then
the board prints the raw range ("Sep 1 – Jun 30").

**Purge Cloudflare's `/robots.txt` once**, after the deploy that moved it out of `public/`: the
edge holds a copy with `max-age=31536000` and keeps serving it whatever the origin returns. Later
changes need no purge (the controller sends a one-hour cache).

**Turn Cloudflare's Always Online on** (or add a Cache Rule for `/robots.txt`). Robots.txt is now
served by the app, so it goes down with Puma, and a 5xx robots.txt stops Googlebot crawling the
site. The controller's `stale-if-error=86400` does not help: Cloudflare honours it only on
Enterprise, and a dead Puma is a 521/522 that serve-stale cannot cover.

## Pretix performance sync

A Bedlam show is a pretix **event series**, so a subevent maps one-for-one onto an
`EventOccurrence`. `events.pretix_sync_performances` turns it on; `Pretix::PerformanceSync` runs
from `Pretix::SyncPerformancesJob` every 15 minutes.

- **The sync is one-way: nothing writes performances to pretix.** One organizer, no staging copy
  (`Pretix::Settings.writes_enabled?`), so a bug editing a live series cannot be undone, where one
  editing our database can.
- **Ownership rides on `event_occurrences.pretix_subevent_id` alone.** A row with one is pretix's
  (times and `sold_out` overwritten each pass, destroyed when the subevent goes); a row without is
  hand-typed and never touched. `access_flags`, `note` and `cancelled` belong to the producer on
  both kinds and are never written by the sync.
- **A hand-typed row at exactly the same `starts_at` is adopted** (keeping its flags and note), not
  duplicated. A row at a different time is left alone.
- **pretix answers `403`, never `404`, for an event it will not show you**, so "shop not built yet"
  and "token lost access" look identical. `Client#events_readable?` (one organizer-level read per
  run) separates them; a token that can read nothing stays loud.
- **A series that does not exist yet is a waiting state, not an error**: written to
  `events.pretix_sync_error` and shown as a banner on the admin event page, never raised or reported
  (ticking the box before building the shop is the normal order). `pretix_synced_at` records the
  last good read. Write both with `update_columns` (`update!` would file a PaperTrail version every
  15 min).
- **`cancelled` is a human statement; the sync never infers it.** pretix has no cancellation
  (`active: false` also means not on sale yet), and a wrong cancelled on a public page is the worst
  error here. A cancelled row outlives its subevent, keeping its id so a restored date reattaches.
  `is_public: false` is treated as gone. `best_availability_state: null` is not sold out.
- **The sync fetches before it writes**, so a timeout leaves the run standing; the job isolates
  each event so one broken event cannot stop the rest.
- **A show syncs only once "Sync performances from pretix" is ticked on its edit page**; new shows
  start unticked.
- **`accepts_nested_attributes_for :event_occurrences` must reject only a row with no id and no
  `starts_at`** (the empty "Add" template). A synced row renders its times as text, so editing its
  flags posts no `starts_at`, and a blanket rule silently discarded the change.
- Cancelled and sold out are badges on the performance's own row, mapped to schema.org
  `EventCancelled` / `SoldOut`; cancelled outranks sold out everywhere. **The box office board
  deliberately shows neither**: its layout is measured in pixels and a badge needs its own design
  pass.

## Opportunities

An `Opportunity` is a posting (a "project"). It `belongs_to :company` (optional), `has_many :roles` (`OpportunityRole`: a position + `category` enum), and carries `project`/`author`, the `compensation_type`/`experience_level` enums, `apply_url` and `email_visibility`/`contact_email`. `title` is optional: `display_title` (and `to_label`) fall back to "Company: Project", enforced by the `has_display_title` validation.

- **Submission is public** (`GetInvolvedController#new/#create`, honeypot + reCAPTCHA). A logged-out submitter gives `submitter_name`/`submitter_email` and has no creator (`external?`); a member is the creator. On the admin form a manager may pick another creator, or enter an external submitter, which records the manager as creator (`on_behalf_of?`: both present). `attribution_label` renders all three cases; `creator_or_submitter` requires one of the two. Every submission starts `approved: false`. A public submission cannot create a `Department` (`OpportunityRole#existing_department_only`): an unknown name goes into the role's note as "Department: <name>" for the reviewer to add on the admin form. The public filter lists `Department.with_listable_roles` only.
- **Listing** (`get_involved#opportunities`): `Opportunity.listable` (the public set) + Ransack filters (company, compensation, experience) + a `?category=` tab, EUTC first. `active` is `listable` ordered internal-first. Per-society share links use `?q[company_slug_eq]=…`. **`ransackable_attributes` on Opportunity and Company list only what the searches and sort headers use**: a wider list let `q[contact_email_start]` read out an email `email_visibility` hides, letter by letter.
- **`OpportunityCardComponent`** renders the project and its roles on the public list and the home/dashboard widgets.
- **Review** is the `Opportunity Reviewer` role, who also gets the `OpportunityDigestJob` digest. Approve/reject emails `notification_email` via `OpportunityMailer`, with an optional note: the creator when present (so an on-behalf decision goes to the internal user), else the external submitter. The `close` member action (aliased to `:update` in Ability) expires a posting at once.
- `Company` (name, `acts_as_url` slug, `internal` EUTC flag) is managed in `Admin::CompaniesController`.

## SEO and structured data

Metadata is in `MetaHelper` (rendered by `layouts/application`), structured data in `SchemaHelper`,
the sitemap in `SitemapsController`.

- **Derive `og:title`, `og:url` and the canonical at render time in `MetaHelper`, never in
  `ApplicationController#set_globals`.** That `before_action` runs before the action sets `@title`,
  so `@title` reads `nil` there. Anything that reads `@title` belongs in `MetaHelper`.
- **`MetaHelper::CANONICAL_PARAMS` is `page` alone, and `page=1` is dropped.** That folds Ransack's
  `?q[...]` space onto the page it filters; adding `q` reopens an unbounded crawl space, and keeping
  `page=1` makes the canonical create a duplicate.
- **`robots.txt` is served by `RobotsController`, never from `public/`**, where the static
  middleware would shadow the route and `public_file_server.headers` would cache it for a year. It
  disallows the same `q` space and must spell it percent-encoded (`q%5B`), since crawlers match
  against the encoded URL.
- **Variants say `format: "webp"`, never `convert:`.** `ActiveStorage::Variation#content_type`
  reads `:format` alone, so `convert:` serves WebP bytes labelled PNG/JPEG, which og:image
  validators reject. Changing a variant re-keys its URL and regenerates the whole set on first
  request.
- **In `ImageComponent`, `full_width` is styling and `priority` is loading.** Pass `priority` only
  for a genuine LCP element; everything else stays lazy.
- **The sitemap reads every record through `Ability.new(nil)`**, so it never lists a URL that
  answers 403 to a crawler.
- **Member profiles are indexed on purpose; never add a blanket `noindex`.** Opting out is
  `users.public_profile`, the flag the guest ability's `:view_shows_and_bio` reads, so an
  opted-out profile is neither in the sitemap nor reachable.
- **An event with performances emits a `@graph`: the run plus one `TheaterEvent` per
  `EventOccurrence`**, each a top-level node with a `superEvent` link (Google reads rich results
  off top-level items only). An event with no occurrences emits the single date-only node.
- **`offers` use `ticket_prices`, one named `Offer` per band, and fall back to the `PRICE_PATTERN`
  scrape.** Keep the fallback: much of the archive has no bands. It fires only when a number can be
  read, because a wrong price in a rich result is a promise the box office must honour.
- **Event and news slugs never change on rename**: an event's URL is its slug alone, so a moved
  slug would 404 every shared link (a news URL leads with its id). `Sluggable` fills only a blank
  slug, and `slug_generator_controller` treats a saved record's slug as chosen. Clearing the slug
  field is the one way to get a new one.
- **`accessibilityFeature` carries only real access provision** (`captions`, `audioDescription`,
  `signLanguage`, `relaxedPerformance`), never scheduling labels such as preview or press night.
- **Never relativise links in an email.** `render_markdown`'s `LinkNormalisationHelper` makes a scheme-less target
  absolute and turns a link to our own host into a path; the second is dead in an email, which has
  no base URL. `MdHelper#normalise_hrefs` passes `relativise: web_request?`, false in a mailer, so
  `MassMailer` newsletters keep absolute links. `test/mailers/mass_mailer_test.rb` pins both halves.
- **AI crawlers (`GPTBot`, `OAI-SearchBot`, `ChatGPT-User`, `ClaudeBot`, `PerplexityBot`) are
  blocked at Cloudflare with a 403, not in the app.** Nothing in this repo controls it.

# Testing
Start the test database using `docker start /mysql8` before running any tests.

- **After touching a Stimulus controller or a stylesheet, run `RAILS_ENV=test bin/vite build`**, or
  about four tests fail with "Vite Ruby can't find entrypoints/admin.js", looking unrelated. In a
  worktree keep `public/vite-test` a real directory, never a symlink to another checkout's: once
  the JS differs the auto-build fails and every request test errors, or tests run the other JS.
  Admin flashes appear only through JavaScript, so a page served without its bundle also fails
  `assert_text "… saved"`, looking flaky.
  - **If a worktree's `node_modules` is a symlink to another checkout, build with
    `pnpm_config_verify_deps_before_run=false RAILS_ENV=test bin/vite build`.** Otherwise pnpm 11's
    dependency check (also run by the test auto-build) tries `pnpm install`, which would purge the
    other checkout's modules; only the missing TTY stops it. Never set `CI=true` there, and never
    pass `--clear` (it deletes `node_modules/.vite` through the link).
- **A functional test cannot pin the order of nested-attribute rows.** `ActionController::TestCase`
  encodes params with `Hash#to_query`, which sorts the keys (`"10"` lands between `"1"` and `"2"`).
  Anything reading row position (`TeamMemberOrdering`) needs an `ActionDispatch::IntegrationTest`,
  which keeps insertion order as a browser does: `test/integration/admin/team_member_ordering_test.rb`.
- **`ActionController::TestCase` reuses one controller instance for every request in a test**, so
  memoised ivars (`@store`, `@budgets`) from the first request serve the next. Don't loop
  different scope values through one functional test.
- **A functional test renders the admin layout, and the sidebar carries the page's year and centre
  onto every scoped finance link**, so `assert_select "a[href=?]"` on a scoped finance path can be
  satisfied by the sidebar alone. Scope it to `main a[href=?]`, or give `text:`.
- **`assert relation.all { … }` always passes**: `Relation#all` ignores the block and returns a
  truthy relation; use `all?`. Likewise `assert a, b` treats `b` as the failure message; use
  `assert_equal`.
- **A system test can never see a hover colour**: Tailwind v4 wraps `hover:` and `group-hover:` in
  `@media (hover: hover)`, which headless Chrome reports false. Assert the classes in a request
  test.
- **A system test needing a server-side failed save on a form with `required` fields sets
  `form.noValidate` first, and asserts the error banner**: otherwise the browser blocks the submit
  and the test passes without reaching the server.
- **The suite runs in parallel**, capped at 8 workers in `test_helper.rb` (past the physical cores
  workers contend, and the shared MySQL is its own ceiling). `PARALLEL_WORKERS=1` debugs serially.
  System tests are pinned to 1 worker (`application_system_test_case.rb`): in parallel they are
  flaky and no faster.
  - Rails splits only the database per worker, so **any new shared filesystem or process state
    must be split in `parallelize_setup`**, as the ActiveStorage disk root and `tmp/generators`
    are (SimpleCov names each worker through its own fork hook). A teardown removes
    `ActiveStorage::Blob.service.root`, never a hardcoded `tmp/storage` (another worker's data).
  - Relaxing MySQL durability on the `mysql8` container (`innodb_flush_log_at_trx_commit=2`,
    `sync_binlog=0`, `--skip-log-bin`) moves the optimum to 12 workers, about 10% faster. Not done:
    it also affects the dev database. Use `PARALLEL_WORKERS=12` if you set it.
- **Never put a dev-only gem in the `:test` group.** `better_errors` + `binding_of_caller` there
  crashed parallel workers (an unmarshalable `Binding` on every exception) and
  `BetterErrors::Middleware` swallowed app-server errors in the test stack, hiding real system-test
  failures. System tests surfacing server errors is them working.
- **A slow suite is usually the machine.** Check `powerprofilesctl get` first: `power-saver` runs
  about 5x slower than `performance`. The tell is a local run losing to CI. Don't trust `/proc/cpuinfo`
  MHz, which reads ~500 either way.
- **Minitest 6 made `load_plugins` opt-in**, so a `minitest/*_plugin.rb` on the load path never
  runs unless you require it and push onto `Minitest.extensions`.
- **No mocking library**: no mocha, no `minitest/mock` (minitest 6 dropped it). Never write
  `.stubs`/`.stub`; stub external services by toggling their config (e.g. a reCAPTCHA failure via
  `Recaptcha.configuration.skip_verify_env.delete("test")` and no token).
- **Validation messages are i18n-customised** ("must not be blank."). Assert
  `errors[:field].present?`, not Rails' default string.
- **A new admin table header or search field needs a key under `simple_form.labels.defaults` in
  `config/locales/simple_form.en.yml`**, or the page raises "Translation missing" (`TableComponent`
  translates symbol headers, `SearchFormHelper` a field's `slug:`).
- **A ViewComponent gets no `paginate` helper.** A component that paginates 500s, and only a test
  rendering it with enough rows sees it: delegate it to `helpers`, as
  `Admin::Reimbursements::AreaClaimsComponent` does.
- **Nothing in the suite renders component previews**, so a broken one goes unnoticed. A preview
  must give the template everything it reads: records where it builds links, and a
  `Kaminari.paginate_array(…).page(1)` list where it paginates.
- **Fixtures with an explicit `id:` break association-by-label.** `test/fixtures/users.yml`'s
  `admin` has `id: 1`, but `creator: admin` sets the FK to the hashed
  `ActiveRecord::FixtureSet.identify(:admin)`, so the association loads `nil` though `creator_id` is set. Reference the id (`creator_id: 1`) when the association must resolve.
- **`MdEditorComponent` cannot be driven by Playwright `fill`**: on submit it syncs its
  contenteditable over the hidden textarea, so the form fails with a blank description. Test such
  forms with a request-level `post :create`; rendering and other Stimulus behaviour (e.g.
  `nested-form` Add/Remove) still test fine in the browser.
- **Capybara's `select` cannot drive a `.simple-select2` select**: `select_controller.js` hides it
  behind Tom Select, so it raises `ElementNotFound`. Click `.ts-control`, then the
  `.ts-dropdown-content .option` (`tom_select_click`), or set it through the widget's API
  (`tom_select`, `tom_select_add`), all in `test/application_system_test_case.rb`. Tom Select
  fires a native `change`, so bound Stimulus actions still run.
- **Capybara's `fill_in` types the first four characters of a value over 30 characters** and sets
  the rest by JavaScript, so a Tab among them leaves a textarea (`ID\tStatus` became `IDtatus`).
  Set a TSV outright (`paste_sheet` in `expense_import_js_test.rb`).
- **Turbo drops a redirect's URL fragment**, so an anchored redirect (`…#card-12`) never reaches
  the browser.
- **`ActiveStorage::FileNotFoundError` in system tests usually means a poisoned test DB, not a
  regression.**
  `ActiveStorageHelper#default_image_blob` finds the placeholder blob by filename without checking
  the file exists; a `bin/rails runner -e test` that rendered an event page commits the row (runner does not roll
  back), and
  the next teardown wipes the file. If the `active_storage_default%` blobs' `created_at` is from
  your session, destroy those rows; the next render re-uploads them.
- **Mutation testing: one mutation at a time, and commit first.** Two mutations together can
  cancel into a false green, and a `git checkout <file>` reverting a mutation also destroys any
  uncommitted fix in that file.
