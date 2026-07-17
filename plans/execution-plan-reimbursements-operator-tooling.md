# Execution plan: reimbursements-operator-tooling findings (229 items)

## Context

The 25-round review at `plans/code-review-reimbursements-operator-tooling.md` produced 229
ranked findings but no execution order. This plan turns that flat, severity-sorted list into
work batches: related fixes (same file, same root cause, same failure class) are grouped so
they ship together as one PR, and batches are ordered by actual risk — money-safety first,
cosmetics last — rather than by the finding numbers or discovery order.

Two categories are deliberately **not** scheduled into a tier, per instruction to keep them
visible rather than drop them silently — see "Deferred / out of scope" at the end.

Every finding number below refers to its numbered entry in
`plans/code-review-reimbursements-operator-tooling.md` — read the entry there for the full
failure scenario and suggested fix; this plan only names the grouping and order.

## Tier 0 — Payment-integrity core (do first, one interlocking cluster)

Why first: this is the only cluster where the failure mode is literally "EUSA pays someone
twice, or pays the wrong amount, and nobody finds out." Everything else assumes this layer is
trustworthy.

**0a. Stop `BatchProcessor` from lying about success.** #2 is the root cause: `process`
unconditionally sets `success = true` after the draft+batch exist, swallowing every downstream
failure. Fix this first because #175, #206, #213, #218, #28 are all *consequences* of the same
swallowing behavior at different call sites (orphan-draft branch skips `notify_producers`;
`notify_producers` gets an unfiltered expense list; `mark_notified`'s write-failure is
absorbed; `receipts_offloaded` is stamped true regardless of upload success;
`producer_notifications_sent` is stamped true regardless of send success). Fix #2's
propagation model once, then each of #175/#206/#213/#218/#28 becomes a small, mechanical
follow-on in the same file.
Also in this batch: #182 — add the `fail_updates` toggle to `FakeAirtableClient#update_record`
(currently the *only* reason this whole failure class is untestable) and write the regression
tests these fixes need to hold.

**0b. Guard every status-changing write against a stale/raced status.** #58 (approve/reject no
current-status check), #106 (reopen can't tell a draft was already sent), #83 (create_batch
retry can create a duplicate, untracked Batch record), #141 (a crash between a successful batch
build and the operator notification silently no-ops on retry), #148 (`draft_message_id` write
has no retry, unlike `create_batch!` itself), #217 (reconcile's per-row loop has no
per-iteration rescue, and notifies only after the whole loop finishes), #125 (reconcile
mid-loop failure permanently orphans a row — kept live per the MySQL note, since the real fix
is a DB transaction, not an Airtable workaround).
Also: #176 (duplicate-submission detector is cosmetic-only, never consulted by `approve`),
#126 (`approve` only checks bank details, ignores budget/amount/receipt/over-budget flags the
UI already computes).

**0c. Fix the BACS spreadsheet's structural cap.** #1 — the 32-row template overflow. Separate
code path from 0a/0b but same stakes (a wrong number reaches EUSA), and small enough to do as
its own one-file fix + regression test in this tier rather than waiting.

Suggested PR boundary: 0a+0b as one PR (they share `batch_processor.rb`/`review_controller.rb`/
`reconcile_controller.rb`), 0c as a second, independent PR.

## Tier 1 — Bank-detail & amount validation correctness

Why second: once the write paths can't silently corrupt state, close the gaps that let a wrong
bank detail or wrong amount get *into* those write paths in the first place.

- **Modulus-check algorithm bugs** (verified against the real spec): #200 (exception 6 wrong
  digit pair), #201 (exception 7 zeroes 6 of 8 weights, not 8), #202 (9-digit Santander/A&L
  numbers hard-rejected instead of `OUTSIDE_SPEC`). Fix all three together, same file
  (`modulus_check.rb`), same spec document to re-check against.
  Ride-along test fixes for the same file: #204 (the #201 regression test can't actually detect
  the bug — fix it *as part of* fixing #201, not separately), #149 (4 of 6 exceptions have zero
  test coverage — add alongside), #127/#129 (two tautological tests that pass regardless of
  correctness — tighten while in the file).
- **Normalization/write divergence**: #167 (`ModulusCheck` strips all non-digits before
  validating; `BacsXlsx` writes the raw un-normalized value — the two disagree on the same
  string), #109 (finance-side bank-detail overrides have zero format validation and bypass
  `BacsXlsx`'s formula-injection sanitizer). One fix: validate at the write path
  (`ExpenseEditsController#update_attrs`) using the same normalizer the check uses, and sanitize
  the bank-detail cells in `BacsXlsx#write_row` like the free-text cells already are.
- **Amount-parsing divergence**: #3 (`AmountValidation` uses `Float()`, `Mapper` uses `to_f` —
  disagree on hex-looking input), #164 (same divergence, `amount_excl_vat` specifically, causes
  a silent no-op write with a false "Saved" flash). Unify on one parser used by validation *and*
  the write.
- **Override-consistency gap**: #147 (payee/sort-code/account-number overrides can be set
  independently, producing an internally-inconsistent spliced payee), #32 (`amount_excl_vat <=
  amount` not enforced on the finance write paths, unlike the submitter form).
- **Small related fixes, same area**: #192 (clearing a budget link silently no-ops due to
  `.compact` stripping the nil), #87 (editing bank details doesn't reset `verified: false`),
  #225 (`mark_verified` doesn't consult the modulus-check result it renders right next to the
  button).

Suggested PR boundary: modulus-check bugs + their tests as one PR; the validation/normalization
gaps as a second PR.

## Tier 2 — The zero-sentinel bug (one root cause, three sites)

Ruby's `0` is truthy, but `amount_excl_vat: 0`/`amount: 0` are documented "not yet known"
sentinels. Three independent places don't special-case it: #61 (reconciliation's
`compare_amount` fallback), #131 (`needs_attention_reasons` never checks gross `amount`), #205
and #211 (`missing_completion_fields`, ex-VAT and gross amount respectively). Fix with the same
`.nil? || .zero?` pattern everywhere (mirroring the one place — `ReviewSupport`'s ex-VAT check —
that already gets it right), in one PR, with one shared regression-test pattern
(`amount: BigDecimal("0")`) reused across all four sites.
Ride along: #133 (no upper-bound sanity ceiling on parsed amounts — same validation layer,
cheap to add at the same time).

## Tier 3 — Job reliability & idempotency

Why third: once the data itself is trustworthy, harden the unattended jobs that act on it.

- **Mailbox poll**: #4 (no idempotency key tying a created expense to its source message —
  crash-then-duplicate risk), #39 (per-cost-centre loop has no isolation, unlike
  `NightlyBatchJob`), #84 (mark-read-then-move non-atomic, can silently unfile a message), #85
  (a mid-loop attach failure skips the submitter reply entirely), #183 (AI checker sends the raw
  Airtable attachment URL, which can be stale by the time a cache-outage-served record reaches
  it).
- **Concurrency/timing**: #5 (all three `limits_concurrency` calls default to a 3-minute lock
  TTL, shorter than realistic job runtime), #40 (`AiCheckJob` has no rescue, relies on opaque
  `retry_on`-then-discard), #208 (worse than #40 assumed: `AiChecker` never raises at all, so a
  transient blip becomes a *permanent* one-shot lockout with no recheck path — fix both
  together, they're the same code path).
- **Nightly-run alerting**: #65 (`record_nightly_run!` fires even when `notify` swallowed a
  send failure), #142 (same non-atomicity, opposite direction: a crash *after* a real send but
  *before* the record write re-sends the same alert), #187 (worse still: the record write can
  itself raise and get caught by the outer rescue, firing a false "FAILED" email on top of a
  real success) — all three are the same "send and record aren't atomic" root cause across
  `NightlyBatchJob`'s three outcome handlers; fix once. #168 (`remind_stale_pending` has no
  dedup key of its own and can resend daily under a persistent failure) and #203
  (`CredentialsCheckJob`'s daily secret-expiry warning has no dedup at all, unlike every
  comparable alert in the diff) are the same missing-dedup pattern, worth fixing alongside.
  #222 (`NightlyBatchJob`/`BuildBatchJob` don't escalate `GraphAuth::AuthError` to the IT alert
  path `MailboxPollJob` already has) closes the last gap in this cluster.
- **Token/client reuse** (currently dormant, cheap, do opportunistically): #194 and #207
  (`GraphClient`/mailbox client token isn't memoized per job run, causing avoidable extra OAuth
  round-trips).
- **Small independent fixes**: #75 (AI-check idempotency guard also defeats retry of the Turbo
  broadcast specifically), #12 (no concurrency guard on `AiCheckJob` — **note**: the review file
  lists this alongside the deprioritized Airtable-caching findings since the failure mode is
  framed as wasted API budget, but the fix itself — `limits_concurrency` keyed on
  `expense_record_id` — is a generic idempotency guard unrelated to Airtable vs. MySQL;
  judgment call whether to fold it in here or genuinely defer it).

Suggested PR boundary: mailbox-poll fixes as one PR, nightly/concurrency fixes as a second.

## Tier 4 — Security hardening

- #59 (receipt image/PDF content sent to Gemini with no prompt-injection defense — the one gap
  in an otherwise-fenced pipeline), #108 (payee `Person#name` reaches the same AI-check prompt
  completely unfenced, unlike every other untrusted field), #111 (prompt-fence regex only
  matches ASCII dashes, missing Unicode homoglyphs) — one AI-safety PR.
- #29 (inbound email producer-attribution trusts the `From` header alone, no SPF/DKIM check, no
  per-sender rate limit).
- #66 (no magic-byte verification on receipt uploads, unlike the app's existing Marcel-based
  `Attachment` model).
- #150 (bank sort code/account number aren't in `filter_parameter_logging.rb`'s allow-list — they
  land in plaintext in the production log at `info` level on every save; this is a one-line fix,
  do it regardless of what else in this tier gets prioritized).
- #95 (persisted SharePoint `drive_id`/`folder_id` are never re-verified against Graph before
  saving — a forged/stale value silently redirects where bank-detail-bearing files upload to).

## Tier 5 — Cost-centre data-model gap (foundational, currently dormant)

Every item here shares one root cause: `Expense`/`Budget`/`Batch` carry no cost-centre link
field, so anything that needs to scope by cost centre either can't, or hardcodes "the default."
All are explicitly dormant today (only one `CostCentre` row exists) but become live bugs the
moment a second cost centre is created — which this diff's own `CostCentre` model is built to
support. Fix once, as a real schema/model change, before standing up a second cost centre:
#41 (`BuildBatchJob` has no cost-centre scoping), #80 (`remind_stale_pending` runs
cost-centre-unscoped ahead of a guard meant to prevent exactly this), #118 (reconciliation
matchers never check `cost_centre`), #214 (`reopen`'s stale-draft cleanup hardcodes the default
mailbox because `Batch` has nowhere to store the real one).
Ride along: #117 (`CostCentre#eusa_code`/`receive_mailbox`/`send_mailbox` have no uniqueness
validation — same model, same PR, prevents a duplicate-mailbox misconfiguration once a second
row is seeded).

## Tier 6 — Data validation completeness

Presence/format gaps on write paths that have no validation at all today: #49 (`Budget` name/
nominal_code presence), #50 (`budget_type` inclusion check), #71 (cost-centre email fields have
no format check), #86 (Build Batch's free-text EUSA-recipient field has no email-format check —
distinct from #71's model-level field), #144 (submitted link-field ids like `budget_record_id`
aren't checked to resolve to a real record before writing, causing an unhandled 500 instead of a
flash).
**Skip**: #151 (`nominal_code` uniqueness across budgets) — per the note already in the findings
file (line 698), budgets sharing a nominal code is intentional (one code, several per-show
budgets), not a bug. Leave it out of any fix.

## Tier 7 — Consolidation / duplication cleanup (mechanical, low-risk, do before the surface grows more)

All of these are "a shared base already exists but the seam was hand-copied instead of hoisted"
— safe to batch into a couple of refactor-only PRs with no behavior change, ideally before more
controllers/jobs/views get added on top of the copies.

- **Controller seams onto `FinanceController`**: 19c (`checker_builder`, 3 copies), 19d
  (`notifier_builder`, 2 copies), 19e (`graph_builder`, 3 copies), 19f (`find_expense!`, 2
  copies), #219 (generalize 19f into a `find_or_404` helper covering 6 call sites total), #215
  (pagination one-liner, 4 copies). One PR: consolidate all six onto `FinanceController`.
- **Job seams onto a new `Reimbursements::ApplicationJob`**: #44 (`store_builder`/
  `graph_builder`/`notifier_builder`, up to 4 copies), #52 + #190 (log+Honeybadger boilerplate,
  10 sites across jobs *and* controllers — give this one a home both layers can reach, not just
  the new job base class).
- **View/email partial dedup**: 19a (expense-edit-form + receipts-manager partials, two full
  views), #45 (email summary-table + sign-off, 7 templates), #74 (reconcile preview's three
  near-identical tables), #121 (budget variance-color logic, duplicated instead of using the
  `ReimbursementsHelper` this diff introduced specifically to prevent that), #210 (43 hand-copied
  Tailwind form-control class strings — needs a new `reimbursements_input_classes` helper,
  mirroring `ButtonComponent`), #197 (3 badge-rendering helpers share one shape), #227 (the one
  badge that bypasses `BadgeComponent` entirely, reaching into its internals — fits naturally
  alongside #210/#197's cleanup).
- **Service-layer dedup**: 19b (receipt add/remove controller actions), #69 (Extractor/
  AiChecker's identical Gemini-call scaffolding), #92 + #172 (Settings' 3 near-identical
  check-and-rescue bodies), #146 (the two vendored-data-file parsers), #185 + #224 (the
  date/decimal parse-and-degrade helper, hand-rolled in 6+ places and already drifting — do
  this one with care since #185 flags the copies have *already* silently diverged, i.e. there's
  a real bug hiding in the duplication, not just style), #189 (`link_actual_to_expense!`/
  `link_actual_to_budget!` identical bodies), #178 (the `expenses.sum { |e| e.amount || 0 }`
  pattern, 10 sites).
- **Test-double dedup**: #46 (`FakeNotifier`, 2 files), #152 + #184 (`FakeChecker`, 5 files
  total), #90 (finance-role test-setup boilerplate, 7 files — use the existing
  `grant_finance_permission` helper).
- **Small standalone simplifications** (low value alone, fine to fold into whichever PR above
  touches the same file): #72, #73.

## Tier 8 — Accessibility sweep

Batch by pattern rather than by file — same fix, applied everywhere the pattern recurs:
- **Missing `aria-live` on dynamically-updated regions**: #10, #26.
- **Missing `scope="col"` on tables**: #16, #48, #96, #216 — one pass across all email templates
  and admin tables.
- **Missing/mismatched labels**: #11, #34 (label `for` mismatch), #35, #47 (error not wired via
  `aria-describedby`), #70 (native `disabled` hides the reason from AT).
- **Repeated context-free accessible names** (the biggest single cluster): #116 (original 4
  files), #169, #180, #220 — one fix (a record-scoped `aria-label` helper) applied everywhere.
- **Static hint text not wired via `aria-describedby`**: #153 (4 locations), #170, #181 — same
  fix, more locations.
- **Decorative glyphs not `aria-hidden`**: #76, #221 — same fix, two more instances.
- **Structural gaps**: #54 (day-checkbox group needs `fieldset`/`legend`), #136 (tab switcher
  needs `role`/`aria-current`), #62 (popover reparents to `<body>`, breaking AT discoverability
  of its own content), #195 (popover's `aria-haspopup="true"` claims a menu role it doesn't
  have — fix alongside #62 since it's the same trigger), #128 (email templates ship with no
  document structure at all).

Suggested PR boundary: one PR per bullet group above (roughly 6 small PRs), since each is a
self-contained, mechanically-verifiable pattern.

## Tier 9 — Test-coverage backfill

Only what isn't already picked up as a ride-along fix in a tier above. Group by file to keep
each PR's diff coherent:
- `graph_client.rb`/`graph_auth.rb`: #18, #105, #226.
- `settings_controller.rb` + its test fakes: #53, #114.
- `budgets_controller.rb`/`batches_controller.rb`: #98, #100, #101, #103, #143.
- `review_controller.rb`/`expense_edits_controller.rb`: #102, #104, #138.
- `reconcile_controller.rb`/`reconciliation.rb`: #68, #159, #160, #165.
- `batch_processor.rb`/`store.rb`: #43 (needs the `fail_updates` toggle — same one #182 in Tier
  0 already adds, so do this after Tier 0), #67, #155, #162.
- `nightly_batch_job.rb`: #97, #157, #158.
- `mailbox_poll_job.rb`: #99, #163 (batched minor gaps).
- Misc small: #7, #8, #9, #17, #24, #25, #156, #166, #177, #223, #229 (rewrite the
  false-confidence test once #193's presence validation lands — check Tier 6/wherever that
  validation gets added first).

## Tier 10 — Low-priority / cosmetic / no urgency

Style-only or genuinely low-impact items, safe to leave for whenever: #21, #22, #23, #27, #51,
#55, #56, #57, #93, #94, #112, #115, #120, #130, #139, #166 (already Tier 9), #173, #174, #186,
#188, #191, #196, #198.

## Deferred / out of scope (kept, not scheduled)

**Airtable-caching/API-budget findings** — the review file itself already deprioritizes these
given the planned MySQL migration: #30, #37, #38, #60, #64, #77, #112 (already listed above as
a Tier 10 quick-win — it's a one-line fix), #119, #122, #123. Not worth spending effort on a
caching layer about to be replaced.

**Scope-contaminated findings** — real issues, but describe code outside this diff's pinned
range (either pre-existing on `main` and unchanged by this branch, or added by later commits
already merged past this review's snapshot): #88, #89, #113, #124, #132. These need their own
audit against current `main`/branch HEAD rather than being folded into this plan, since this
plan's tiers are all scoped to what this diff actually changed.

## Verification

Each tier above should land with `bin/rails test` green (full reimbursements suite: 583+ runs
today) plus the specific regression test named in its findings' "Suggested fix" — the review
file already spells out the exact test case for nearly every finding. Tier 0 in particular
should not be considered done until `#182`'s `fail_updates` toggle exists and there's a test
proving `BatchProcessor` no longer reports `success = true` when a downstream write fails.
