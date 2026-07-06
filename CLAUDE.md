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
- **The dev container is mise-driven — keep it in sync.** [.devcontainer/Dockerfile.dev](.devcontainer/Dockerfile.dev)
  installs *only* the `mise` binary plus OS build/runtime libs; `mise.toml`/`mise.lock` are the single
  source of truth for Ruby, Node, and the dev tools, installed by `mise install` in
  [.devcontainer/setup.sh](.devcontainer/setup.sh). **Never** pin a language version in the devcontainer
  (no `ruby:x.y` base, no `apt-get install nodejs`) — that reintroduces drift. When you change the
  toolchain (a new mise tool, a Ruby/Node bump) or the dev-env standard (`DEV_ENV_VERSION`), check
  whether the devcontainer needs a matching change: new native build deps go in `Dockerfile.dev`, new
  bootstrap steps go in `setup.sh`. The mise toolchain is cached on the `mise-data` compose volume.

## Dev Server

- **Run with `bin/dev`** — foreman ([Procfile.dev](Procfile.dev)) supervising Puma (`bin/rails server`) + Vite (`bin/vite dev`). Assume it is already running; ask the user to start it rather than starting one yourself.
- **No restart needed for app code** — models, controllers, views, etc. are auto-reloaded on the next request.
- **To reload boot-time state** (`config/initializers`, `config/*`, `Gemfile`, env vars, new/enum-backed DB columns): run **`bin/restart-web`** — see its header comment for the mechanics and why `touch tmp/restart.txt` does nothing here.
- **For a full stack restart** (e.g. `vite.config` or JS dependency changes): `Ctrl-C` the `bin/dev` terminal and rerun it, or in VS Code run the "Dev server" task again (Tasks: Restart Running Task).

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

## Opportunities

An `Opportunity` is a posting (a "project"): it `belongs_to :company` (optional) and `has_many :roles` (`OpportunityRole`, a position + `category` enum). It carries `project`/`author`, `compensation_type`/`experience_level` enums, an `apply_url`, and `email_visibility`/`contact_email`. `title` is optional — `display_title` (and `to_label`) fall back to "Company: Project", enforced by the `has_display_title` validation.

- **Submission is public.** Anyone may submit via `GetInvolvedController#new/#create`; logged-out submitters provide `submitter_name`/`submitter_email` (creator is `nil` → `external?`), protected by a honeypot + reCAPTCHA. Members are attributed to their account; managers can pick a different creator on the admin form. A manager entering an external submitter there is recorded as the creator (`on_behalf_of?` — creator *and* submitter present); `attribution_label` renders all three cases. All submissions are `approved: false` until reviewed. `creator_or_submitter` requires one or the other.
- **Listing** (`get_involved#opportunities`): `Opportunity.listable` (the public set) + Ransack filters (company/compensation/experience) + a `?category=` tab, sorted EUTC-first. `active` = `listable` ordered internal-first. Per-society shareable links use `?q[company_slug_eq]=…`.
- **Display:** one `OpportunityCardComponent` renders the project + role sub-list for the public list and the home/dashboard widgets.
- **Review:** `Opportunity Reviewer` role; approve/reject email whoever actually submitted (`OpportunityMailer`, `notification_email` — the account creator when present, so on-behalf decisions go to the internal user, else the external submitter) with an optional note. Reviewers also get the `OpportunityDigestJob` digest. A `close` member action (aliased to `:update` in Ability) expires a posting immediately.
- `Company` (name + `acts_as_url` slug + `internal` EUTC flag) is admin-managed via `Admin::CompaniesController`.

# Testing
Start the test database using `docker start /mysql8` before running any tests.

- **Validation/error messages are i18n-customised** (e.g. presence reads "must not be blank.", not Rails' default "can't be blank"). Assert on `errors[:field].present?` rather than the literal default string.
- **Admin search-form/index table headers** translate symbol headers via `t("simple_form.labels.defaults.<key>")` (see `SearchFormHelper` and `shared/_table.erb`). A new column used as a header or search field needs a matching key in `config/locales/simple_form.en.yml` under `simple_form.labels.defaults`, or the page raises "Translation missing".
- **The markdown editor (`Admin::MdEditorComponent`) cannot be driven by Playwright `fill`** — it syncs its contenteditable into the hidden description textarea on submit, overwriting injected values, so the form re-renders with a blank-description error. Cover any form with a description editor via request-level functional tests (`post :create`) rather than a browser submit; form rendering and other Stimulus interactions (e.g. the `nested-form` Add/Remove buttons) still verify fine in the browser.
- **Fixtures with an explicit `id:` break association-by-label references.** Some fixtures set an explicit `id:` (e.g. `test/fixtures/users.yml` `admin` has `id: 1`). Referencing such a record by label in another fixture's association (`creator: admin`) sets the foreign key to `ActiveRecord::FixtureSet.identify(:admin)` — a *hashed* id that does **not** equal the explicit `id`, so the loaded association (`opportunity.creator`) comes back `nil` even though `creator_id` is set. When a test relies on the association resolving, reference the explicit id directly (`creator_id: 1`), not the label.
- **No mocking library:** the suite has neither mocha nor `minitest/mock` (minitest 6 dropped it). Don't write `.stubs`/`.stub`. Stub external services by toggling their config instead (e.g. force a reCAPTCHA failure with `Recaptcha.configuration.skip_verify_env.delete("test")` and no token in the request).