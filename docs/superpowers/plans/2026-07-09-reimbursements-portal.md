# Reimbursements Portal Implementation Plan

> **STATUS (2026-07-09):** Tasks 1–13 implemented and committed on
> `reimbursements-portal` (full suite green: 1851 runs, 0 failures, +105 new tests).
> Remaining before merge: Mick's manual setup (mailbox, Entra app, fnox secrets — see
> the setup guide), visual check + real-Airtable E2E with `bin/dev` in this worktree,
> and Mick's explicit merge approval.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Producer-facing reimbursements portal (my-expenses + AI receipt-first submission + email-in receipts) inside Black Lightning, backed by the existing Airtable base.

**Architecture:** No local expense storage — a cache-fronted `Reimbursements::Store` wraps a field-ID-based Airtable REST client; PORO models mirror bedlam-bacs' dataclasses. Gemini extracts receipt data; a Solid Queue recurring job polls an M365 shared mailbox via app-only Graph auth. One Rails migration (`users.airtable_person_id`).

**Tech Stack:** Rails 8.1, Net::HTTP (no new gems), Solid Cache, Solid Queue, Devise (existing), Gemini 2.5 Flash REST, Microsoft Graph REST, Minitest with injected fakes (no webmock — repo has no mocking library, per CLAUDE.md stub via config/DI).

**Spec:** `docs/superpowers/specs/2026-07-09-reimbursements-portal-design.md`

## Global Constraints

- Airtable free plan ≈1,000 API calls/month shared with bedlam-bacs: warm-cache portal visit = 0 Airtable calls; global expense list cached 10 min; people/budgets 1 h; every write busts.
- No Airtable schema changes. All reads/writes by **field ID** (`returnFieldsByFieldId=true`, payloads keyed by field ID, `typecast: true`).
- Required fields stay required in portal forms: budget, type, amount, amount excl VAT, description, ≥1 receipt, payment reference. VAT missing on receipt = soft block (acknowledge checkbox), never hard.
- Cost centre config carries EUSA code: `F40` Fringe now, `BED` termtime later.
- Email-in reply = link to the expense in the portal only, no inline summary.
- Secrets live in **per-environment Rails credentials** under `reimbursements:` (`azure_tenant_id`, `azure_client_id`, `azure_client_secret`, `azure_secret_expires_on`, `airtable_pat`, `gemini_api_key`, `alert_email`) — BL has no dotenv; this matches the existing `mailsender` pattern. Matching `REIMBURSEMENTS_*` ENV vars override credentials when set (Kamal flexibility). Access only via `Reimbursements::Settings`. Airtable base/table/field IDs likewise in per-env credentials under `reimbursements_airtable` (dev + production; test env uses injected configs).
- **Entra secret expiry (Mick, 2026-07-09):** warn the IT subcommittee before the client secret expires — daily check job emails `alert_email` + Honeybadger from 30 days out (using `azure_secret_expires_on`), and Graph `invalid_client` auth failures trigger an immediate (once-per-day deduped) alert.
- BL conventions: Tailwind v4, `btn_classes`/`ButtonComponent.classes_for` (never Bootstrap classes), ViewComponents need a preview, i18n'd validation messages (assert `errors[:field].present?`, not literals), hk pre-commit runs rubocop/herb/tests — commit code+test together.
- All new Ruby namespaced `Reimbursements::`; services in `app/services/reimbursements/`, POROs in `app/models/reimbursements/`.

---

### Task 1: Airtable config from credentials

**Files:**
- Create: `app/services/reimbursements/airtable/config.rb`
- Create: `test/services/reimbursements/airtable/config_test.rb`
- Modify: shared credentials (`bin/rails credentials:edit`) — add `reimbursements_airtable:` (converted from bedlam-bacs `config/field_ids.toml`)

**Interfaces:**
- Produces: `Reimbursements::Airtable::Config.new(hash)` and `.from_credentials`; `#base_id`, `#table_id(:expenses)`, `#fid(:expenses, :amount)`, `#status_label(:pending)`, `#field_name(:expenses, "fldXXX")` (reverse lookup). Raises `KeyError` on unknown keys.

- [ ] Write failing tests: construct from a nested hash (`{base_id: "app1", tables: {expenses: "tbl1"}, fields: {expenses: {amount: "fldA"}}, status_options: {pending: "Pending"}}`), assert lookups + KeyError on unknowns.
- [ ] Implement `Config` as a frozen wrapper with deep-symbolized keys; `.from_credentials` reads `Rails.application.credentials.reimbursements_airtable` and raises a clear error when missing.
- [ ] Tests green; commit `feat(reimbursements): airtable field-id config`.
- [ ] Add real IDs to shared credentials via `bin/rails credentials:edit` (non-interactive EDITOR script), copying values from `~/Stack/Programmeren/bedlam-bacs/config/field_ids.toml` (tables: people/budgets/expenses; fields per example file; status_options; base_id from bedlam-bacs `.env` `AIRTABLE_BASE_ID`). Batches/actuals tables not needed. Verify with `bin/rails runner` printing table ids. Commit `chore: reimbursements airtable ids in credentials`.

### Task 2: PORO models + status

**Files:**
- Create: `app/models/reimbursements.rb` (module), `app/models/reimbursements/status.rb`, `person.rb`, `budget.rb`, `attachment.rb`, `expense.rb`
- Test: `test/models/reimbursements/expense_test.rb`, `person_test.rb`

**Interfaces:**
- Produces: keyword-init POROs mirroring bedlam-bacs `models.py`:
  - `Status::PENDING/APPROVED/SUBMITTED/PAID/REJECTED` (strings, `Status.all`, `Status.badge_variant(status)`)
  - `Person#record_id/name/email/sort_code/account_number/verified/notes`, `#bank_details?`
  - `Budget#record_id/name/nominal_code/active`, `Attachment#attachment_id/filename/url/size_bytes/content_type`
  - `Expense#record_id/auto_number/person/amount(BigDecimal)/amount_excl_vat(BigDecimal|nil)/budget(Budget|nil)/description/receipts/status/expense_type/payee_name_override/sort_code_override/account_number_override/payment_reference/rejection_reason/submitted_at/ai_check_status/ai_comment`
  - `Expense#pending?`, `#editable?` (== pending?), `#needs_completion?` (missing budget, amount, amount_excl_vat, payment_reference, description or receipts), `#payee_override?`
- Note: `budget` and `person` are nilable (email-in gaps / unlinked records) — unlike bedlam-bacs.

- [ ] Failing tests: construct expense, assert `editable?` only when Pending; `needs_completion?` true when budget nil / payment_reference blank; false when complete.
- [ ] Implement POROs (plain classes, keyword `initialize`, `attr_reader`, defaults matching models.py).
- [ ] Green; commit `feat(reimbursements): domain POROs`.

### Task 3: Airtable client + mapper

**Files:**
- Create: `app/services/reimbursements/airtable/client.rb`, `app/services/reimbursements/airtable/mapper.rb`
- Test: `test/services/reimbursements/airtable/client_test.rb`, `mapper_test.rb`

**Interfaces:**
- Consumes: `Config` (Task 1), POROs (Task 2).
- Produces:
  - `Client.new(config:, token: ENV.fetch("REIMBURSEMENTS_AIRTABLE_PAT"), http: nil, sleeper: nil)` — `http` is a callable `(method, uri, headers, body) -> [status_int, body_string]`; default implementation uses Net::HTTP. `sleeper` callable for 429 backoff (default `->(s){ sleep s }`).
  - `#list_records(:expenses)` → array of raw record hashes (handles pagination via `offset`, always `returnFieldsByFieldId=true`)
  - `#create_record(:expenses, fields_by_id)` / `#update_record(:expenses, record_id, fields_by_id)` (both `typecast: true`) → raw record hash
  - `#upload_attachment(record_id, field_key, filename:, content_type:, bytes:)` → posts base64 to `content.airtable.com/v0/{base}/{record}/{fieldId}/uploadAttachment`
  - Raises `Reimbursements::Airtable::Error` (with `status`) on non-2xx after one 429 retry (30 s per Airtable docs).
  - `Mapper.new(config)`: `#expense(record, people_by_id:, budgets_by_id:)` → `Expense`; `#person(record)` → `Person`; `#budget(record)` → `Budget`; `#expense_fields(attrs)` → `{fieldId => value}` accepting symbol keys (`:amount, :amount_excl_vat, :budget_record_id, :person_record_id, :description, :payment_reference, :expense_type, :status, :payee_name_override, :sort_code_override, :account_number_override`); linked records become `[record_id]`; BigDecimal → `to_f` for JSON.
- [ ] Failing mapper tests: raw record (fields keyed by fld ids from a test config) → Expense with joined person/budget; attrs → field-id payload; nil budget tolerated.
- [ ] Implement Mapper.
- [ ] Failing client tests with fake `http` recording requests: pagination (two pages via offset), create posts typecast+field ids, 429 then success retries once and calls sleeper(30), 500 raises Error, upload_attachment hits content.airtable.com with base64.
- [ ] Implement Client.
- [ ] Green; commit `feat(reimbursements): airtable client and mapper`.

### Task 4: Cost centre config

**Files:**
- Create: `app/models/reimbursements/cost_centre.rb`
- Test: `test/models/reimbursements/cost_centre_test.rb`

**Interfaces:**
- Produces: `CostCentre::FRINGE` (frozen instance: `key: :fringe, name: "Bedlam Fringe 2026", eusa_code: "F40", mailbox: "reimbursements@bedlamfringe.co.uk"`), `CostCentre.default` → FRINGE, `CostCentre.all`. (BED termtime = future entry.)

- [ ] Test + implement + commit `feat(reimbursements): cost centre config`.

### Task 5: Store (cache-fronted repository)

**Files:**
- Create: `app/services/reimbursements/store.rb`
- Test: `test/services/reimbursements/store_test.rb`

**Interfaces:**
- Consumes: Client, Mapper, Config.
- Produces (all controller/job access goes through this):
  - `Store.new(client: nil, config: nil, cache: Rails.cache)` (defaults build real ones)
  - Reads: `#expenses` (all, cached `reimbursements/expenses` 10 min), `#expenses_for(person_record_id)`, `#find_expense(record_id)` (from cached list), `#people` (cached 1 h), `#person_by_email(email)` (case-insensitive), `#find_person(record_id)`, `#active_budgets` (cached 1 h, expense-type only, sorted by name)
  - Writes (each busts the relevant cache and returns the mapped PORO): `#create_expense!(attrs)`, `#update_expense!(record_id, attrs)`, `#create_person!(name:, email:)`, `#update_person!(record_id, attrs)`, `#attach_receipt!(expense_record_id, filename:, content_type:, bytes:)`
  - `#refresh_expenses!` (delete cache key)
- Cache TTL/keys are constants: `EXPENSES_KEY/TTL`, `PEOPLE_KEY/TTL`, `BUDGETS_KEY/TTL`.
- Tests use a fake client returning canned record hashes + `ActiveSupport::Cache::MemoryStore`; assert second read = 0 client calls, write busts, `person_by_email` matches case-insensitively.

- [ ] Failing tests → implement → green; commit `feat(reimbursements): cached store`.

### Task 6: User↔Person link (migration + resolver)

**Files:**
- Create: `db/migrate/*_add_airtable_person_id_to_users.rb`
- Create: `app/services/reimbursements/person_link.rb`
- Test: `test/services/reimbursements/person_link_test.rb`

**Interfaces:**
- Produces: `PersonLink.new(store:)`: `#person_for(user)` → Person|nil (stored id first, else email match which persists `user.update_column(:airtable_person_id, ...)`); `#ensure_person!(user)` → Person (creates People record from user's name/email when absent, persists link). Use the User display-name method that exists (check `app/models/user.rb`, e.g. `name` / `full_name` / `name_or_default`) — verify at implementation time.

- [ ] Migration `add_column :users, :airtable_person_id, :string` + `bin/rails db:migrate` (annotaterb re-annotates user.rb — commit both).
- [ ] Failing tests with fake store + user fixture: stored-id path, email-match persists link, ensure creates person.
- [ ] Implement; green; commit `feat(reimbursements): user-person link`.

### Task 7: Gemini extractor

**Files:**
- Create: `app/services/reimbursements/extractor.rb`
- Test: `test/services/reimbursements/extractor_test.rb`

**Interfaces:**
- Consumes: `Budget` list for suggestions.
- Produces: `Extractor.new(api_key: ENV["GEMINI_API_KEY"], http: nil)`; `#extract(receipts:, budgets:, context: nil)` where receipts = `[{filename:, content_type:, bytes:}]`, context = optional email subject/body text. Returns `Extraction` struct: `merchant, purchase_date(Date|nil), total_amount(BigDecimal|nil), vat_amount(BigDecimal|nil), vat_itemised(bool|nil), suggested_description, suggested_budget_record_id(nil unless matches a provided budget), suggested_payment_reference(≤18 chars), ok?(bool), error(nil|String)`. Never raises; returns `ok?: false` extraction on HTTP/parse errors or missing api_key.
- Model `gemini-2.5-flash` REST `:generateContent`, `generationConfig.response_mime_type: application/json` + `response_schema`; prompt includes budget names+ids and the payment-reference guidance (invoice-specified ref > invoice number > "<merchant> <purpose>" ≤18 chars).
- **Graceful failure + retry (Mick, 2026-07-09):** extraction failure must never block creating the expense — callers proceed with blank prefill (portal) or a receipt-only expense (email-in). Transient errors (timeouts, network, 429, 5xx) retry with exponential backoff up to **5 attempts** (waits 1, 2, 4, 8 s via injectable `sleeper:`); non-transient (4xx, missing key, malformed response) fail immediately. Final failure → `ok?: false`.

- [ ] Failing tests with fake http: happy parse into struct incl. BigDecimal amounts + budget id validated against provided list (bogus id → nil); malformed JSON → ok? false; missing key → ok? false without calling http; 500 twice then success → ok? true with sleeper called [1, 2]; five 500s → ok? false with sleeper called [1, 2, 4, 8]; 400 → ok? false with no retry.
- [ ] Implement; green; commit `feat(reimbursements): gemini receipt extractor`.

### Task 8: Portal — routes, base controller, my expenses

**Files:**
- Modify: `config/routes.rb` (namespace `:reimbursements`: `resources :expenses, only: %i[index new create edit update] do collection { post :extract } end; resource :payment_details, only: %i[edit update]`, root to expenses#index)
- Create: `app/controllers/reimbursements/base_controller.rb`, `app/controllers/reimbursements/expenses_controller.rb` (index + refresh param), views `app/views/reimbursements/expenses/index.html.erb`, `app/components/reimbursements/status_badge_component.rb` (+ template + preview)
- Test: `test/functional/reimbursements/expenses_controller_test.rb`, `test/components/reimbursements/status_badge_component_test.rb`

**Interfaces:**
- Consumes: Store, PersonLink, Status.
- Produces: `BaseController < ApplicationController` with `authenticate_user!`, handles CanCanCan conventions (check `ApplicationController` for `check_authorization` enforcement; skip if required for non-AR), helpers `store`, `current_reimbursements_person`; scopes all data to `current_reimbursements_person`.
- Index: status badges (`StatusBadgeComponent` — variant per status), amount, budget name, description, rejection reason when rejected, "needs completion" banner when `needs_completion?`, edit link when `editable?`, refresh button (`?refresh=1` → `store.refresh_expenses!`), empty state with portal explainer + link to new.

- [ ] Failing functional tests: unauthenticated → redirect to sign-in; signed-in with fake store (inject via controller helper or `Store` stub seam — add `BaseController#store` memoized, tests override with a tiny subclass or `Reimbursements::Store.stub` is unavailable (no mocha) so inject via `request.env` or a settable class attribute `Store.test_instance` guarded to test env — pick the cleanest: `BaseController.store_builder` class attribute, defaulting to `-> { Store.new }`).
- [ ] Implement controllers/views/component (+preview); green incl. herb lint; commit `feat(reimbursements): portal my-expenses page`.

### Task 9: Payment details page

**Files:**
- Create: `app/controllers/reimbursements/payment_details_controller.rb`, `app/models/reimbursements/payment_details_form.rb` (ActiveModel), views `edit.html.erb`
- Test: `test/functional/reimbursements/payment_details_controller_test.rb`, `test/models/reimbursements/payment_details_form_test.rb`

**Interfaces:**
- Produces: `PaymentDetailsForm` (ActiveModel::Model; `name, sort_code, account_number`; validates presence, `sort_code` 6 digits after stripping `-`/space, `account_number` 8 digits). Update path: `ensure_person!` then `store.update_person!`. Index shows a prompt banner when person missing bank details.

- [ ] Form validation tests → implement → controller tests (edit renders, update writes via fake store, invalid re-renders 422) → green → commit `feat(reimbursements): payment details`.

### Task 10: AI-first submission (new/create/extract)

**Files:**
- Create: `app/models/reimbursements/expense_form.rb`, views `new.html.erb` + `_form.html.erb`, Stimulus `app/javascript/controllers/reimbursements_receipt_controller.js` (posts receipt to `extract`, fills form fields, char counter for payment reference)
- Modify: `app/controllers/reimbursements/expenses_controller.rb` (new/create/extract)
- Test: `test/models/reimbursements/expense_form_test.rb`, functional tests for create/extract

**Interfaces:**
- Produces: `ExpenseForm` (ActiveModel): fields `expense_type` (Reimbursement/Invoice/From EUSA…, labels from bedlam-bacs `ExpenseType` values), `amount`, `amount_excl_vat`, `budget_record_id`, `description`, `payment_reference`, `payee_name_override/sort_code_override/account_number_override` (invoice only; sort/account format checks when present), `receipts` (uploaded files, ≥1 required on create), `vat_acknowledged` (checkbox), `vat_itemised` (hidden, from extraction, default "unknown").
  - Validations: presence of amount/amount_excl_vat/budget/description/payment_reference/receipts; amount > 0; amount_excl_vat ≤ amount; payment_reference ≤ 18 chars (form truncates JS-side, server validates); **soft VAT block**: error on `vat_acknowledged` when `vat_itemised == "false"` (or excl == incl) and not acknowledged, message explaining the ex-VAT budget rule.
- `create`: `ensure_person!` → `store.create_expense!(status: Pending, person, all fields)` → `attach_receipt!` per file → purge tmp uploads (uploads arrive as ActionDispatch Http UploadedFile — no ActiveStorage blobs needed; read bytes directly, ≤5 MB guard per file with friendly error) → redirect to index with success flash.
- `extract` (POST, multipart): runs `Extractor`, returns JSON of extraction + `budgets` unchanged; failure → `{ok: false}` and the form stays manual.

- [ ] Form tests (incl. both VAT-soft-block branches) → implement form.
- [ ] Functional: create happy path writes expense + attachments via fake store; create without receipt 422; extract returns extraction JSON with fake extractor (inject like store).
- [ ] Views + Stimulus (progressive enhancement: form fully usable without JS).
- [ ] Green; commit `feat(reimbursements): ai-first expense submission`.

### Task 11: Edit pending expenses

**Files:**
- Modify: `expenses_controller.rb` (edit/update), reuse `_form` (no receipt requirement on edit; show existing receipt filenames)
- Test: functional edit/update tests

**Interfaces:** `edit` 404s unless expense belongs to current person AND `editable?`; `update` maps form → `store.update_expense!`; new receipts optional on edit (attach if provided).

- [ ] Failing tests (scoping: other person's expense 404; non-pending 404; update writes) → implement → green → commit `feat(reimbursements): edit pending expenses`.

### Task 11b: Settings + secret-expiry alerting

**Files:**
- Create: `app/services/reimbursements/settings.rb`, `app/jobs/reimbursements/credentials_check_job.rb`, `app/mailers/reimbursements_mailer.rb` (+ views `secret_expiry_warning`, `auth_failure`)
- Modify: `config/recurring.yml` (daily 8am credentials check)
- Test: `test/services/reimbursements/settings_test.rb`, `test/jobs/reimbursements/credentials_check_job_test.rb`, mailer test

**Interfaces:**
- `Settings.azure_tenant_id` etc. — each reads `ENV["REIMBURSEMENTS_<KEY>"]` first, then `Rails.application.credentials.dig(:reimbursements, :<key>)`. Also `Settings.azure_secret_expires_on` (Date|nil), `Settings.alert_email`, `Settings.configured?(:mailbox)` guards.
- `CredentialsCheckJob#perform`: if expiry date present and `<= 30.days.from_now` → `ReimbursementsMailer.secret_expiry_warning` to alert_email + Honeybadger event (context: days remaining). Nothing otherwise.
- `ReimbursementsMailer.auth_failure(detail)` — used by MailboxPollJob when MailboxClient raises `AuthError` (Graph `invalid_client`/AADSTS7000222), deduped to once/day via `Rails.cache.fetch("reimbursements/auth-failure-alerted", expires_in: 1.day)`.

- [ ] Tests → implement → green → commit `feat(reimbursements): settings + entra secret expiry alerts`.

### Task 12: Graph mailbox client

**Files:**
- Create: `app/services/reimbursements/mailbox_client.rb`
- Test: `test/services/reimbursements/mailbox_client_test.rb`

**Interfaces:**
- Produces: `MailboxClient.new(mailbox:, settings: Reimbursements::Settings, http: nil, clock: -> { Time.current })`:
  - `#unread_messages` → array of `Message` structs (`id, from_address, subject, body_text, has_attachments`)
  - `#attachments(message_id)` → `[{filename:, content_type:, bytes:}]` (fileAttachment contentBytes base64-decoded; skips inline/non-file)
  - `#reply(message_id, html:)`, `#mark_read_and_move(message_id, folder)` (folder :processed/:rejected; `#ensure_folders!` creates them if missing, memoized folder ids)
  - Token: client-credentials against `login.microsoftonline.com/{tenant}/oauth2/v2.0/token`, cached until expiry (re-fetch when <60 s left).
- Tests with fake http: token fetched once for two calls; unread query filters `isRead eq false`; reply posts comment; move hits move endpoint; ensure_folders creates missing folder.

- [ ] Failing tests → implement → green → commit `feat(reimbursements): graph mailbox client`.

### Task 13: Mailbox poll job + recurring schedule

**Files:**
- Create: `app/jobs/reimbursements/mailbox_poll_job.rb`, `app/views/reimbursements/mailer_replies/` (3 HTML partials rendered via `ApplicationController.render` or inline heredocs — keep simple: private methods returning HTML strings with the portal link)
- Modify: `config/recurring.yml` (`reimbursements_mailbox_poll: class: Reimbursements::MailboxPollJob, queue: default, schedule: every 5 minutes`)
- Test: `test/jobs/reimbursements/mailbox_poll_job_test.rb`

**Interfaces:**
- Consumes: MailboxClient, Store, Extractor, PersonLink (person lookup by email only — no user needed).
- Produces: `perform` — skip entirely (log once) unless ENV credentials present. For each unread message:
  1. `store.person_by_email(from)` nil → reply "not recognised" (+ portal/finance@ pointers) → move :rejected.
  2. No file attachments → reply "please attach the receipt as PDF/photo" → move :rejected.
  3. Else: extract (attachments + subject/body context, budgets from store) → `store.create_expense!` (Pending, person, extracted amount/excl-vat/description/suggested budget/suggested reference — blanks where extraction nil; description falls back to email subject) → attach each receipt → reply with link `edit_reimbursements_expense_url(record_id)` → move :processed.
  - Any exception per message: log + `Honeybadger.notify`, leave message unread (retry next cycle); reply-then-move ordering per spec.
- Tests with fakes covering all three branches + error-leaves-unread + env-missing no-op.

- [ ] Failing tests → implement → green → hk `zizmor`/`database_consistency` unaffected → commit `feat(reimbursements): mailbox poll job`.

### Task 14: Finish line

- [ ] `hk run check --all` in worktree (rubocop, herb, eslint, jscpd, tests, brakeman…) — fix fallout.
- [ ] Full `bin/rails test` green.
- [ ] Update `CLAUDE.md` (short Reimbursements section: architecture, cache discipline, env vars) + `docs` guide already committed.
- [ ] Manual E2E once Mick's secrets exist: portal submit against real base; poll job dry run (`bin/rails runner "Reimbursements::MailboxPollJob.perform_now"`); verify in bedlam-bacs Review page.
- [ ] Merge decision per global CLAUDE.md: touches auth'd surface + secrets setup → **pause and ask Mick before merging.**
