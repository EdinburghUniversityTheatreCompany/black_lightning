# Reimbursements Issues Round — Implementation Plan

> **For agentic workers:** This plan is executed by Opus subagents, one per track, coordinated
> from the main session. Each track is a self-contained brief. Before starting a track, read
> `plans/findings-reimbursements-issues-2026-07-23.md` — the section named in your track holds
> the detailed investigation (exact line numbers, verified patches, designs). Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the fixes and features arising from the 2026-07-23 reimbursements investigation:
two bug fixes, bank-detail encryption, a consent-based AI extraction flow, the Airtable
post-flip cleanup, budget overview + exports + actuals-import improvements, a cost-centre form,
and a Fringe-generalisation/em-dash copy sweep.

**Architecture:** Work is grouped into tracks with disjoint file footprints, dispatched in
waves. Each track runs in its own git worktree (Agent tool `isolation: "worktree"`), commits
atomically, and is merged serially into `main` by the coordinator, who runs the full suite at
each merge. The copy sweep runs last so it never conflicts with feature tracks.

**Tech Stack:** Rails 8.1, minitest, Stimulus/Vite, Tailwind v4, caxlsx/rubyXL, ActiveRecord
Encryption, RubyLLM (Gemini 2.5 Flash), Microsoft Graph.

## Global Constraints

- **Test DB is shared** (single MySQL container, no parallelize). Wrap every test run in
  `flock /tmp/bl-test.lock -c "…"` so concurrent agents serialize. Start it with
  `docker start mysql8` (idempotent).
- **TDD per superpowers:test-driven-development**: failing test first wherever the change is
  testable. Functional tests over system tests; the markdown-editor Playwright caveat and all
  rails-toolkit:rails-core rules apply.
- **No em dashes in any new user-facing copy** (Track D removes the existing ones; don't add
  more). No hardcoded "Bedlam Fringe" in new code — derive from `CostCentre`.
- **Never call the Airtable client directly**; after Track A, the Airtable layer no longer
  exists — everything goes through `Reimbursements::DatabaseStore` via `Reimbursements.build_store`.
- **Multi-database app**: rollback via `bin/rails db:rollback:primary STEP=n`. New tables
  default bigint PKs (fine — all `reimbursements_*` tables are modern bigint).
- **AI prefill must never block** submission; VAT soft-block stays a soft block.
- **Commits are atomic**, one logical change each; branch from local `main` HEAD.
- The uploaded `2024-2025 F40 actuals.csv` (repo root, untracked) is **real finance data —
  never commit it**. Use it read-only for parser verification and to derive **anonymised**
  fixtures (fake names, keep structure/refs/amounts shape).

## Wave order

| Wave | Tracks | Rationale |
|---|---|---|
| 1 | A (Airtable cleanup), B (URI fix + outbound gating), F (encryption) | Foundations; everything later builds on the post-Airtable store. |
| 2 | C (cost-centre form), E (extraction consent), G (budget overview) | Feature tracks with disjoint footprints. |
| 3 | H (exports), I (actuals: offsets + convert) | H depends on A; I touches `expense_form` after E is merged. |
| 4 | D (Fringe generalisation + em-dash sweep) | Sweep over final code; would conflict with everything if earlier. |

Coordinator merges tracks within a wave serially (A → B → F, etc.), resolving small overlaps
(`settings.rb`, `test_helper.rb` are touched by both A and B), running
`flock /tmp/bl-test.lock -c "bin/rails test"` after each merge.

---

### Track A: Airtable post-flip cleanup

**Findings section:** none (this is the cleanup CLAUDE.md and
`docs/reimbursements/mysql-migration-and-roadmap.md` already promise). Read the roadmap doc first.

**Files:**
- Delete: `app/services/reimbursements/airtable/` (entire dir: client, mapper, config, store POROs),
  `app/services/reimbursements/store.rb` (the Solid-Cache-fronted Airtable store),
  `app/services/reimbursements/airtable_importer.rb`, importer rake task(s) under `lib/tasks/`.
- Modify: `app/services/reimbursements.rb` (`build_store` returns `DatabaseStore` unconditionally;
  delete backend switching), `app/services/reimbursements/settings.rb` (remove `backend`/Airtable
  keys), `app/services/reimbursements/store_queries.rb` (keep — but it now has one includer; fold
  into `DatabaseStore` if that leaves the code smaller), `app/controllers/admin/reimbursements/status_controller.rb`
  (drop the Airtable reachability check), `test/support/reimbursements_test_helpers.rb` (delete
  `FakeAirtableClient`, `build_fake_store`), delete Airtable-era store tests, `config/initializers/`
  any Airtable cache config, `db/schema.rb` untouched (keep `airtable_record_id` columns — they're
  historical data; just stop writing them).
- Docs: update `CLAUDE.md` (Reimbursements portal section: remove backend-switch paragraphs),
  `docs/reimbursements/mysql-migration-and-roadmap.md` (mark cleanup done).

**Steps:**
- [ ] `rg -l "REIMBURSEMENTS_BACKEND|Airtable|airtable"` across `app/ lib/ config/ test/ docs/ CLAUDE.md`
  and build the full kill list before deleting anything (CLAUDE.md rule: full scope first).
- [ ] Delete the Airtable layer; make `Reimbursements.build_store` return the database store
  unconditionally; remove `REIMBURSEMENTS_BACKEND` handling everywhere including `test_helper.rb`'s
  forcing line (leave a comment that database is now the only backend).
- [ ] Migrate/delete tests that injected `FakeAirtableClient`; keep equivalent coverage where the
  behaviour under test survives (store caching semantics die with the store).
- [ ] Keep `Reimbursements::Settings` working for the remaining (Graph/Gemini) secrets.
- [ ] Full suite green under flock; update docs; atomic commits per logical step.

**Produces:** a store API identical to today's `DatabaseStore` surface; later tracks add methods
to `DatabaseStore` only.

---

### Track B: Receipt-upload URI fix + dev outbound gating

**Findings sections:** "Root-cause receipt upload bad URI" and "Audit dev sending real emails" —
both contain **verified exact patches**; apply them as written (they were reproduced against this
tree). Summary:

- [ ] TDD: add the failing test from the findings (percent-encoding of
  `Photoshoot props (2).jpeg` in `test/services/reimbursements/graph_client_test.rb`), watch it
  fail with `URI::InvalidURIError`, then apply the one-line `ERB::Util.url_encode` patch at
  `app/services/reimbursements/graph_client.rb:112`. Mirror test for the chunked path.
- [ ] Add `Reimbursements::Settings.outbound_enabled?` (production true; elsewhere requires
  `REIMBURSEMENTS_ENABLE_OUTBOUND`), guards in `MailboxPollJob#perform`,
  `GraphClient#send_mail`, `GraphClient#create_draft` (suppressed draft returns a stub), and the
  `ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = "1"` line in `test/test_helper.rb` — Patches A–E in the
  findings, verbatim.
- [ ] Belt-and-braces guards on `MailboxClient#reply/#move/#mark_read` (per findings caveat; do
  NOT gate inside `GraphAuth#graph_request`).
- [ ] Tests: `outbound_enabled?` truth table; MailboxPollJob no-ops when disabled; send_mail
  suppression logs and returns nil.

**Conflicts:** `settings.rb` + `test_helper.rb` also touched by Track A — coordinator resolves.

---

### Track F: Bank-details encryption at rest

**Findings section:** "Audit bank-details permissions/security" (HIGH + MEDIUM items).

**Files:**
- Modify: `app/models/reimbursements/payment_details.rb` (`encrypts :sort_code, :account_number, :notes`),
  `app/models/reimbursements/expense.rb` (`encrypts :sort_code_override, :account_number_override, :payee_name_override`),
  `app/controllers/admin/reimbursements/people_controller.rb` (`appended_notes`: mask account
  number to last-4, include acting user's name+id in the audit line),
  `config/environments/test.rb` (literal dummy encryption keys — fine in test),
  encryption key config: production → `config/credentials/production.yml.enc`; development →
  `REIMBURSEMENTS_AR_ENCRYPTION_*` ENV via fnox (dev credentials are public — **no keys in
  development.yml.enc**). Wire in `config/application.rb` or an initializer with ENV fallback.
- Create: migration is **not** needed for column types (`string(255)` holds the ciphertext), but a
  backfill task is: `lib/tasks/reimbursements_encrypt_backfill.rake` (`find_each(&:encrypt)` for
  both models), guarded by `support_unencrypted_data = true` until run in production.
- Docs: add a runbook note to `docs/reimbursements/mysql-cutover-runbook.md` (or a new
  `encryption-rollout.md`): deploy with `support_unencrypted_data=true` → run backfill → flip off.

**Steps:**
- [ ] Failing test: write + read roundtrip; assert `ciphertext_for(:account_number)` differs from
  plaintext and the DB column no longer contains the raw digits
  (`Reimbursements::PaymentDetails.connection.select_value` on the raw column).
- [ ] Non-deterministic encryption (default); nothing queries these by value.
- [ ] `appended_notes` test: audit line contains `…1234` last-4 only + acting user; full number
  absent.
- [ ] Verify modulus check + BACS xlsx still see plaintext through the model (they read
  attributes, so they do — prove with the existing BacsXlsx test).
- [ ] Full suite green; note in the PR/merge summary that **production needs the key material +
  backfill before `support_unencrypted_data` can be flipped off** (coordinator surfaces this to
  Mick at merge).

---

### Track C: Cost-centre creation form

**Findings section:** "Design new cost-centre form" — complete scoping; follow it exactly.

Decisions locked: collect only the 5 required fields (`key`, `name`, `eusa_code`,
`receive_mailbox`, `send_mailbox`), redirect to the existing edit page for the rest; **`key` is
auto-derived from `name`** (parameterize) with a format validation (`/\A[a-z0-9-]+\z/`) and an
optional override field shown collapsed ("Advanced"); add `Reimbursements::CostCentre` to the
permissions-grid exclusion list; plain `form_with` + Tailwind, NOT simple_form.

- [ ] Functional tests first (`settings_controller_test.rb`): `get :new` renders; `post :create`
  valid → row + redirect to edit with notice; duplicate `eusa_code`, malformed mailbox, blank name
  → 422 re-render, no row.
- [ ] Route `only: %i[index new create edit update]`; controller `new`/`create` mirroring
  `save_settings` error style; `new.html.erb` mirroring `edit.html.erb` markup; "New cost centre"
  button on the index (`btn_classes(:primary, :sm)`).
- [ ] Permissions grid exclusion + a test asserting the grid excludes it.
- [ ] System test: plain fill+submit is safe here (no markdown editor).

---

### Track E: Extraction consent (three-option) + invoice bank-detail extraction + email-in change

**Findings section:** "Assess Gemini privacy + opt-in scan" (the button design there is the
skeleton — but the product decision is now a **three-option choice**, below).

**Decisions locked (from Mick):**
- On choosing a receipt file, extraction does NOT auto-fire. A required radio group appears:
  1. **"Yes, to be reimbursed to myself"** → extract with today's schema (merchant, amount,
     description, budget match, reference). No bank fields.
  2. **"Yes, as an invoice paid out to the bank details listed on the invoice"** → extraction
     schema additionally returns `payee_name`, `sort_code`, `account_number` (only if printed on
     the invoice); prefills the third-party override trio; modulus/all-or-nothing validation
     unchanged; user must still verify.
  3. **"No, I will fill in all the details myself"** → no network call at all.
- Disclosure copy must be honest about the **free tier**. Draft (Track owner may polish, no em
  dashes, match the portal's plain tone):
  > *Reading the receipt sends it to Google Gemini. We use Gemini's free tier, which means
  > Google may store what we send and humans may review it to improve their products. If your
  > receipt shows anything you'd rather keep private, pick "No" and type the details in
  > yourself.*
- **Email-in stops extracting entirely.** `MailboxPollJob` no longer calls the extractor: every
  inbound receipt becomes a blank draft + the existing "please complete it in the portal" reply
  path (the designed fallback). Delete the job's extractor plumbing and its `context` prompt path
  in `Extractor` if nothing else uses it.

**Files:**
- Modify: `app/views/admin/reimbursements/expenses/_form.html.erb` (remove
  `change->…#extract`; add radio group + disclosure + scan trigger),
  `app/javascript/controllers/reimbursements_receipt_controller.js` (targets for the radios;
  `extract` fires on radio selection of options 1/2, sending `mode`; option 3 inert; re-scan
  allowed; enable only when a file is chosen),
  `app/services/reimbursements/extractor.rb` (schema + prompt gain an `invoice` mode; bank fields
  only requested in invoice mode; 18-char reference cap unchanged),
  `app/controllers/admin/reimbursements/expenses_controller.rb#extract` (accept `mode` param,
  whitelist `%w[self invoice]`; JSON response includes the bank trio only for invoice mode),
  `app/models/reimbursements/expense_form.rb` (no change to validation semantics; prefilled
  overrides flow through existing fields),
  `app/jobs/reimbursements/mailbox_poll_job.rb` (remove extraction; always draft + portal reply).
- Tests: functional `expenses_controller_test.rb` extract-mode coverage (self mode returns no bank
  keys even if the fake extractor supplies them; invoice mode passes them through; invalid mode →
  422); `extractor_test.rb` prompt/schema per mode with FakeChat; `mailbox_poll_job` tests updated
  to assert no extraction call and the portal-completion reply; system test drives the radio +
  scan click (no markdown editor on the receipt part — but the form has the description editor, so
  keep assertions to the prefill JSON/radio enabling, not a full browser submit).

**Steps:** TDD service-level first (extractor modes), then controller, then JS/view, then job.
Never-block invariant: a failed scan leaves the form fully usable; assert the existing
`ok: false` path still renders.

---

### Track G: Budget overview (3 phases)

**Findings section:** "Design budget/forecast overview" — follow its design with these locked
decisions: **Actual = both columns** ("Paid (portal)" and "EUSA actual"); **Pipeline** column =
sum of Pending expenses (Committed stays Approved/Submitted/Paid); **"Expected outturn"** =
`[projected, committed, paid_portal, eusa_actual].compact.max` with tooltip *"the greater of the
current projection and what's already been spent or committed, so the number never drops below
reality"*; over-budget badge semantics unchanged this round; database-only (`DatabaseStore`);
`BudgetUpdate` captures `created_by` (users FK) and batched forecasts stay editable via the
existing per-budget log.

- [ ] **Phase 1 (no migration):** `Budget#projected_amount`, `#paid_portal_amount` (alias of
  `total_paid`), `#eusa_actual_amount` (Σ linked actuals: debits via expenses for Expense
  budgets, credits via `budget_id` for Income), `#pipeline_amount`, `#expected_outturn`; columns
  on budgets index + edit financials card. Model tests first (use `create_reimbursements_*`
  helpers).
- [ ] **Phase 2:** `GET /admin/reimbursements/budgets/overview` — grouped by `nominal_code`
  (budgets listed under a shared code, subtotal row per code, grand total footer), "Unbudgeted
  spend" section for actuals whose nominal matches no budget, `NominalCodeRollup` presenter,
  `DatabaseStore#budgets_by_nominal_code` + `#unbudgeted_actuals`, sidebar + index links,
  `reimbursements_money` helper throughout. Functional test: grouping, subtotals, unbudgeted row.
- [ ] **Phase 3 (migration — flag at merge):** `reimbursements_budget_updates` table +
  nullable `budget_update_id` on forecasts (findings has the migration sketch), `BudgetUpdate`
  model, multi-budget "New budget update" form (one shared date + note, an amount input per
  active budget, blanks skipped), updates index, per-budget log shows the shared note.
  Run `bundle exec annotaterb models` after migrating.

---

### Track H: CSV/xlsx exports

**Findings section:** "Design CSV/xlsx exports" — follow it. Locked decisions: **bank details
masked to last-4** in the People exporter and the combined workbook (BACS xlsx untouched);
Batches sheet is one-row-per-batch; sheet names fixed (no dates); serve workbook inline.

- [ ] `Reimbursements::Exports::Base` + `Expenses`/`Actuals`/`Budgets`/`People`/`Batches`
  exporters; extract `BacsXlsx`'s formula-injection guard into a shared
  `Reimbursements::CellSanitizer` used by Base (this silently fixes the injection gap in the two
  existing CSVs — call it out in the commit message as a security fix).
- [ ] Migrate `ExpenseEditsController`/`ActualsController` onto the exporters; add `format.csv` +
  "Download CSV" links (`request.query_parameters.merge(format: :csv)`) to Budgets, People,
  Batches, Review (reusing `Exports::Expenses`).
- [ ] `ExportsController#show` (finance-gated) building the caxlsx workbook; roo-parse it in the
  functional test (sheet names + a known row + masked account number `****1234`).
- [ ] Budgets exporter includes the new Track G columns (Pipeline, Expected outturn) — G merges
  first.

---

### Track I: EUSA actuals — offset pairing + actual→expense conversion

**Findings section:** "Investigate EUSA actuals import". **Real-data tuning is done** (coordinator
analysed `2024-2025 F40 actuals.csv`, 309 rows, 71 candidate pairs): offset legs are usually on
the **same nominal code** (65/71) — accrual↔reversal and PI↔SI pairs; refs match only ~half
(36/71); same date 33/71, same period 48/71, and legs can straddle **months** (Sep accrual
released Oct; one pair Jul→Mar). A £186.23 genuine expense collides by amount with an unrelated
reversal, so scoring, not filters, prevents false pairs.

**Locked heuristic** (replaces the findings' guessed predicates):
- Candidates: exact same absolute amount, opposite sign, within the same financial year.
- Score each candidate pair: `same_ref*4 + same_nominal*2 + same_period*1 + narrative-prefix
  similarity*1 − date_distance_penalty` (penalty: 0 same day, 1 within 31 days, 2 beyond).
- Greedy highest-score-first; a pair must score ≥ 4 (i.e. at least ref match, or
  nominal+period+narrative agreement) — below that, leave both rows unmatched.
- Preview shows every proposed pair with a **checkbox (default ticked)**; operator can untick
  before apply. Never silent.
- **Offset rows are never convertible to expenses** (Mick's call): apply stamps
  `reconciliation_status: "offset"` + `offset_of_id` self-FK on both legs; the Actuals browser
  badges them, filters them out of the working set by default, and renders no "Create expense"
  button on them.

**Actual→expense conversion** (unlinked debits only): `ExpenseForm.from_actual` per the findings
design; created **directly as Paid** with `payment_confirmed_date = actual.date`,
`expense_type = TYPE_FROM_EUSA`, `require_receipts: false`, VAT/large-amount soft-blocks skipped
for this type; `link_actual_to_expense!` closes the loop; never enters review/batch.

**Files:** per the findings "Exact files to touch" list (reconciliation service + controller +
preview view + migration on `reimbursements_eusa_actuals` + model + `DatabaseStore` +
actuals index/new_expense views + `expense_form.rb`). Migration → flag at merge; annotate models.

- [ ] Parser check first: confirm `parse_actuals_rows` handles the real Sage header set
  (`NLNominalAccounts.AccountNumber`, `NLPostedNominalTrans.GoodsValueInBaseCurrency`,
  `SYSAccountingPeriods.PeriodNumber`, …) by feeding it the first rows of the real CSV **in a
  throwaway script, not a committed fixture**; extend `build_col_map` if any header is missed.
- [ ] Derive anonymised fixtures reproducing the three real pair shapes (same-ref reversal,
  PI↔SI same nominal, cross-month accrual release) plus the false-positive collision; TDD
  `detect_offsetting_pairs` against them.
- [ ] Wire preview card (tickboxes) + apply path + badges/filter, functional tests.
- [ ] `from_actual` conversion with its guards, functional tests both controllers.

---

### Track J: Review screen — approve/reject must not silently drop unsaved edits

**Findings section:** none (added by Mick 2026-07-24).

**Problem:** on the finance review screen, an operator can edit an expense's fields and then hit
Approve or Reject; the decision action submits without the edits, silently losing them.

**Locked UX (Mick's spec, verbatim options):** if the card's form has unsaved changes when
Approve/Reject is clicked, show a confirmation dialog: *"Do you want to save the changes before
approving/rejecting?"* (word it for the action actually clicked) with three buttons:
**Cancel** (close dialog, stay put), **Save Changes** (persist the edits, then perform the
approve/reject), **Discard Changes** (perform the approve/reject without the edits). No dialog
when the form is pristine. `window.confirm` can't do three options — use a `<dialog>` element
driven by a Stimulus controller; buttons styled via `btn_classes` / `ButtonComponent.classes_for`.

**Implementation notes:**
- Investigate first: how the review card's edit form and the approve/reject actions are wired
  (`app/controllers/admin/reimbursements/review_controller.rb`, the manual-edit path near :303,
  `app/views/admin/reimbursements/review/_expense_card.html.erb`) and whether expense_edits'
  full edit page has the same hazard (if so, cover it with the same controller).
- Dirty tracking in Stimulus: snapshot the form's serialized state on connect and after any
  successful save; compare on approve/reject click.
- "Save Changes" must be save-then-decide server-side in one user gesture: either the decision
  action accepts the edited fields (single request), or the JS saves then submits the decision
  on success — but a save validation failure must abort the decision and surface the errors.
- Never-block invariant: with JS off, the buttons keep today's behaviour (document this in the
  code; the dialog is progressive enhancement).
- Tests: functional coverage for "decision with edited params saves then decides" and
  "validation failure aborts the decision"; system test drives the dialog (dirty → dialog with
  the three buttons; pristine → no dialog). Avoid driving the markdown editor if the card has
  one — assert on the dialog mechanics.

---

### Track K: Graph 404 on vanished mailbox messages (prod error 132834366)

**Findings section:** none (Honeybadger report, added 2026-07-24). **Dispatch only after Track B
merges** — same files.

`MailboxPollJob#handle_unknown_sender` → `MailboxClient#mark_read_and_move` → `mark_read`
PATCHed a message that no longer existed (404 `ErrorItemNotFound`; someone had handled/deleted
it in Outlook between the poll's listing and the PATCH). `GraphAuth#graph_request` raises the
generic `Error` for any non-2xx, so a vanished message becomes a Honeybadger alert every cycle
it's retried.

**Fix:** add `Reimbursements::GraphAuth::NotFoundError < Error` raised when status == 404 (in
both `graph_request` and `graph_raw_request`). In `MailboxClient#reply`, `#mark_read`, `#move`:
rescue `NotFoundError`, `Rails.logger.info` ("message gone; nothing to do"), return nil — the
message being gone means there is nothing left to process, retry, or alert on. Do NOT swallow
404s elsewhere (e.g. `GraphClient#upload_to_folder` must still fail loudly — a missing receipts
folder is a real error). TDD with FakeHttp returning a 404 + the real Graph error JSON shape
from the report; assert no raise, nil return, and that the poll loop continues to the next
message.

---

### Track L: Missing attachments-gallery partial (prod error 132814643)

**Findings section:** none (Honeybadger report, added 2026-07-24). Disjoint files — dispatch any
time.

`Admin::QuestionsAndAnswersComponent` renders `'shared/attachments_gallery'`, but the partial
lives at `app/views/admin/shared/_attachments_gallery.html.erb`; every other call site uses the
`admin/shared/attachments_gallery` path. The bad path only executes when an answer has **>1**
attachments, so questionnaires#show 500s exactly then.

**Fix:** correct the path in both branches (flush and non-flush) of
`app/components/admin/questions_and_answers_component.html.erb`. TDD: component test (or
functional questionnaires#show test) with an answer carrying two attachments — fails with
MissingTemplate first, passes after. Sweep per CLAUDE.md: `rg "render ['\"]shared/"` across
`app/` and verify every referenced partial actually exists under `app/views/shared/` (report any
other mismatches and fix them the same way); also add a ViewComponent preview case with two
attachments if the component's preview doesn't cover it.

---

### Track M: the AI check must honour the submitter's consent (found by Mick, 2026-07-25)

**The defect.** `Reimbursements::AiChecker` sends the receipt *files* to Gemini
(`.ask(prompt, with: attachments(expense.receipts))`), exactly as the extractor does, and
`AiCheckJob` is enqueued **by the Review page on load**, one per unchecked Pending expense. So a
producer who ticks "No, I will fill in all the details myself" — explicitly declining to send
their receipt to Google — has it sent anyway, automatically, as soon as finance opens the queue.
Track E's consent flow is hollow without this. All four reviewers missed it.

**Decisions (Mick, 2026-07-25):**
1. **One consent covering both purposes.** The existing radio group is the single decision, and
   its copy must say the receipt may also be used to *check* the claim, not only to read it.
   "No" means no extraction *and* no AI check. Do not add a second question.
2. **No consent on file means no check.** Absent consent is refusal, so every pre-existing claim
   and every email-in claim (no submitter present to ask) stops being AI-checked. Finance reviews
   those by hand, as they did before the checker existed. Verdicts already written stay — don't
   delete history.
3. **No override.** A refusal is final; finance keeps the receipt, the modulus check, owner
   endorsement and their own judgement. The verdict area reads "not checked" with the reason.

**Implementation sketch:**
- Persist the choice on `reimbursements_expenses` as a **nullable boolean** (e.g.
  `ai_processing_consent`): `nil` = never asked, `false` = declined, `true` = consented. Both
  falsey states block the check; keeping them distinct lets the UI say "declined" versus "not
  asked" honestly. Nullable additive column, no backfill (nil is exactly right for old rows).
- The submitter's radio must reach the server **on create**, not only on the extract POST — a
  submitter who picks "No" never fires an extract, so today nothing records their choice. Derive
  the boolean: self → true, invoice → true, no → false.
- Gate in **two** places: `ReviewController` must not enqueue `AiCheckJob` without consent, and
  `AiChecker#check` must refuse independently (defence in depth, since the job is also reachable
  from a console and from any future caller).
- Finance UI: the verdict slot shows "Not checked: the submitter did not consent to AI
  processing" (or "…was not asked" for `nil`) styled as neutral information, **not** as a failed
  check — a declined claim must not look suspicious.
- **Rewrite the disclosure copy** (`_form.html.erb`). Two problems with the current text: it only
  covers reading the receipt, not checking it, and it treats "a receipt goes to Google" as the
  risk. Mick's steer (2026-07-25): a photo of a till receipt is mostly unremarkable, so the copy
  should be proportionate and point at what actually matters, which is **personal details printed
  on the document**. Draft for his sign-off (no em dashes, per this round's own rule):

  > If you say yes, we send the receipt to Google Gemini twice: once now, to read it and fill in
  > this form, and once later, so finance can check your claim against it. We use Gemini's free
  > tier, which means Google may keep a copy and have people look at it.
  >
  > For most receipts that isn't much of a worry. A till receipt for props or paint is
  > unremarkable. It's worth a moment's thought if the document carries personal details, such as
  > a supplier invoice printed with someone's bank details, an order confirmation showing your
  > home address, or anything medical. If you'd rather not, pick "No" and type the details in
  > yourself. Nothing else about your claim changes.

  The three option labels stay exactly as Mick worded them. The closing promise must stay true:
  with no override (decision 3), declining genuinely costs the submitter nothing.
- Tests: consent persisted from the form on create for all three options; the Review page
  enqueues nothing for a nil/false claim; `AiChecker#check` refuses directly; a consented claim
  still checks as before; the verdict partial renders the neutral not-checked state. Email-in
  creates a claim with `nil` and is never checked.

---

### Track N: in-page receipt viewing + side-by-side checking (Mick, 2026-07-25)

Two requests that are really one feature: receipts open in a new tab today, which makes checking
a claim a tab-flipping exercise. Finance compares a figure on a document against a figure in a
form dozens of times in a sitting, so the document and the details should be visible together.

**Decisions (Mick, 2026-07-25):**
1. **Inline viewing everywhere a receipt appears**: the Review page, the finance expense
   edit/show pages, and the producer's own claim pages. Same partial/component in all three, so
   this is one implementation, not three.
2. **Review page layout**: receipt pane beside the details, with a **thumbnail strip** to switch
   when a claim has several receipts (one shown large at a time). Not a stacked scroll, which
   pushes the relevant document off-screen on a multi-receipt claim.
3. **Opened per claim, on demand**, not on for every card. The queue must stay scannable, and
   this also avoids loading every PDF on page load. No persisted per-operator preference.

**Implementation notes:**
- **PDFs**: prefer the browser's native viewer via `<iframe>`/`<object>` pointed at the existing
  `rails_blob_path`, with a visible "open in a new tab" / download fallback for browsers that
  refuse to render inline. Do NOT vendor pdf.js unless native embedding proves inadequate: it is a
  large dependency for a small win here, and `vendor/assets` would be the place if it ever is.
- Images already have `rails_representation_path` thumbnails (`Expense.wrap_receipt`), so the
  thumbnail strip has what it needs for images; PDFs will need a generic document icon rather than
  a real page preview unless a preview is already generated.
- Stimulus controller for the switching and the open/close; no JS framework. Lazy: set the pane's
  `src` when it is first opened so nothing is fetched for a collapsed card.
- Check `Attachment::ALLOWED_CONTENT_TYPES` for what can actually arrive (the sheet-music MIME
  registrations mean the set is wider than images+PDF, e.g. `.mscz`/`.mxl`); anything not
  renderable inline must degrade to the download link rather than an empty frame.
- **Narrow screens**: side-by-side is untenable on a phone, so the pane must stack below the
  details rather than squeezing both. Verify at a mobile width.
- Accessibility: the strip is a list of controls, not decorative thumbnails, so it needs real
  buttons with accessible names ("Receipt 2 of 3, invoice.pdf") and the pane needs a label.
- Tests: request-level rendering for each of the three pages; a system test opening the pane,
  switching receipts, and confirming the PDF frame gets a `src` only after opening; the
  markdown-editor caveat in CLAUDE.md means don't drive the description field in the browser.

---

### Track D: Fringe generalisation + em-dash sweep (CANCELLED)

Mick stopped this agent mid-run on 2026-07-25. The Fringe generalisation (~21 hardcoded
"Bedlam Fringe"/"Bedlam BACS"/`finance@bedlamfringe.co.uk`/`"F40"` sites) and the em-dash sweep
(~71 user-facing prose sites, 6 placeholder glyphs) remain undone, as do two stale "Airtable"
copy lines on the budgets index and reconcile preview. The findings file's tables are the work
list if it is ever picked up. **Do not relaunch without Mick asking.**

### Track D (original brief, retained for reference)

**Findings section:** "Find hardcoded fringe lang + em dashes" — the tables ARE the work list.

- [ ] **A1 items 1–21**: derive from `CostCentre` (`name`, `eusa_signature_name`,
  `receive_mailbox`) — plumb `cost_centre` into `Notifier` assigns once and reuse; contact
  addresses from cost-centre config, never literal. Item 22 (importer) is gone after Track A.
  Also generalise the `"[Bedlam BACS]"` subject prefixes to a cost-centre-derived prefix and fold
  in the `bacs_xlsx.rb` hardcoded `"F40"` fallback (`plans/code-review…md:732`).
- [ ] **B1 items 1–71**: apply the proposed rewrites verbatim (they were drafted per-line);
  re-grep `—` in `app/` afterwards to catch drift from waves 1–3 (new code shouldn't have any,
  but verify).
- [ ] **B2 placeholders**: standardise the six bare `"—"` empty-value glyphs on the helper
  convention (`"-"`, per `reimbursements_helper.rb:84`'s comment) via a tiny shared helper.
- [ ] **B3**: leave comments/logs/`prompt_safety.rb` (that em dash is data) untouched.
- [ ] Tests: existing copy assertions will break where strings changed — update them; add a
  lint-ish test asserting `Notifier` subjects contain the cost-centre name, not "Bedlam".

---

## Coordinator protocol

1. Dispatch each track as an Opus subagent (`model: "opus"`, `isolation: "worktree"`), waves in
   order; agents commit incrementally on their branch and report a summary + test evidence.
2. Merge serially within a wave; run `flock /tmp/bl-test.lock -c "bin/rails test"` on `main`
   after each merge; `bin/rails test:system` after waves 2 and 4 (UI-heavy).
3. **Pause and show Mick** before merging: any migration (F backfill, G phase 3, I), and the
   final Track D diff (broad copy changes).
4. Checkpoint progress in `.claude/current_plan.md` after every merge.
5. After wave 4: `hk run check`, update CLAUDE.md/docs, close out the checkpoint, present the
   production follow-ups (encryption key material + backfill; Gemini key tier decision is
   **out of code scope** but flagged: free tier is now disclosed in-product).
