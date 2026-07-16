# Decisions log: reimbursements execution plan (autonomous work)

Scope calls made while executing `plans/execution-plan-reimbursements-operator-tooling.md`
without stopping to ask — logged here for review in a batch rather than blocking on each one.

## Tier 0b

- **#126 (approve should gate on more than bank details)**: implemented the "at minimum" half of
  the suggested fix only — block on no linked budget and on a zero/blank ex-VAT amount (both
  genuine reconciliation-breaking data-integrity issues). Left the softer reasons (no receipt,
  "possible duplicate", failed modulus check) advisory-only, since blocking approval on those is
  a real UX/workflow decision (an operator may have good reason to approve despite a duplicate
  warning) that I didn't think was mine to make unilaterally. Worth confirming this split is right.

- **#106 (reopen can't tell if a draft was sent)**: implemented the "refuse to reopen" half of the
  suggested fix, not the "require an explicit confirmation checkbox" alternative — simpler, and
  immediately safe. If you'd rather operators could override with an explicit acknowledgement
  instead of being hard-blocked, that's a follow-up UI change.

- **#148 (draft_message_id write has no retry) + #83 (create_batch retry can duplicate a Batch
  record)**: solved both together with one design change — `draft_message_id` now gets written as
  part of the initial `create_batch!` call (not a separate follow-up write), which both closes
  #148 (there's no longer a "batch exists but the field is missing" state possible) and gives
  #83's retry-dedup a natural lookup key. Added `Store#find_batch_by_draft_message_id` (an
  uncached, direct Airtable lookup) so a retry after an ambiguous failure reuses an
  already-created batch instead of creating a duplicate.

- **#141 (a crash between a successful build and the operator notification silently no-ops on
  retry) — DEFERRED, not fixed.** The suggested fix needs new durable state (e.g. an
  "operator_notified" flag on the Batch record) plus retry-detection logic in `BuildBatchJob`,
  which means a new Airtable field (credentials/field-id plumbing + test-helper updates) for a
  genuinely narrow race: the gap is a single in-process method call with no I/O of its own between
  `BatchProcessor#process` returning and `notify(...)` running, so a crash landing in exactly that
  window isn't meaningfully more likely than a crash during `process` itself (already handled
  correctly by the cardinal-rule/orphan-draft guards). Given the effort (schema change) vs. the
  narrowness of the window, I left this for a deliberate follow-up rather than rushing a
  half-built fix. Flag if you want it done anyway.

- **#217 (reconcile per-row loop has no per-iteration rescue)**: fixed — each row's write
  sequence (`create_actual!` → `link` → status update) is now rescued independently, so one row's
  failure can't abort the whole paste or (critically) prevent `notify_paid_producers` from running
  for the rows that did commit. Also added a warning banner on the apply page when any row failed,
  since silently swallowing the error would just reintroduce the same "false confidence" problem
  Tier 0a fixed for `batch_ready`. Did **not** implement the other two threads in #125/#217's
  suggested fix: a "companion check" requiring an Actual to be linked before dedup treats it as
  already-imported, and a UI surface listing orphaned/unlinked Actuals for manual repair — both are
  real gaps but are a genuinely separate feature (a new admin surface), not a contained bug fix.
  Logged as a follow-up, not attempted here.

- **#176 (duplicate-submission detector is cosmetic-only)**: folded "possible duplicate" into the
  Review page's ready/attention partition specifically (in `ReviewController#index`), rather than
  into the shared `ReviewSupport.needs_attention_reasons` helper — that helper has 5+ other call
  sites (expense_edits controller, the nightly job, two more views) that don't compute a
  per-pending-list duplicates map and don't obviously want the same semantics (e.g. the nightly job
  triages *Approved* expenses, where "duplicate among Pending" doesn't apply the same way).
  Widening the shared helper's signature felt like a bigger, riskier ripple than the fix warranted.
  Kept advisory (not a hard block on `approve`) for the same false-positive reasoning as #126 above.

- **#1 (BACS spreadsheet 32-row overflow)**: fixed — extended the vendored template to 200 data
  rows (verified end-to-end via real generated spreadsheets before replacing the file: GRAND TOTAL
  formula, the Authorisation Form's cross-sheet total, and cell styling all round-trip correctly),
  and `BacsXlsx#generate` now raises a clear `TemplateError` above that cap instead of corrupting
  the total. Chose 200 as a round, generous number rather than trying to derive an exact "real"
  cap from usage data — flag if you want a different number.

## Tier 1 (modulus-check + amount/bank-detail validation correctness)

- **#202 (9-digit account numbers)**: implemented the actual Pay.UK §2.1.2 Santander/A&L
  transform (substitute the sort code's last digit with the account's first, check the remaining
  8) rather than the weaker "just degrade to OUTSIDE_SPEC" alternative the finding also offered —
  it's a well-specified, real bank format worth actually supporting. Did **not** attempt the
  related "10-digit accounts need per-institution first-vs-last-8-digit handling" gap the same
  finding flagged as lower-confidence — that needs real per-bank spec data I don't have verified
  access to re-derive, so it's left as-is (already matching the ported bedlam-bacs behavior).

- **#164/#3 (amount-parsing divergence)**: fixed at the root (a stricter decimal-format regex in
  `AmountValidation`, so a value that passes validation can never diverge from what the write path's
  `to_f` produces) rather than also touching `Mapper#expense_fields`'s `to_f` calls — `Mapper`'s
  `to_f` is shared by several unrelated models (Budget, EusaActual), so changing its parsing
  strategy felt like a bigger, riskier ripple than the finding needed. Left the controllers'
  own `.to_f` re-derivation of `amount_excl_vat` untouched too, for the same reason — with the
  regex fix, anything that reaches that line is already guaranteed to parse identically either way.

- **A self-review of this Tier 1 diff caught one real bug in my own fix**: `strip_separators` used
  `\s` (regex whitespace class — matches tab/newline/CR too) instead of a literal space, which
  would have let a tab-containing value slip through the exact strictness the fix was adding.
  Fixed in a follow-up commit (7211750d) with a regression test. Noting this here as a reminder
  that a "review the diff before moving on" pass caught something a same-session author missed —
  worth keeping that habit for the remaining tiers.

- **#1 through #225 (Tier 0 + Tier 1) are now complete.**

## Tier 2 (zero-sentinel amount bug)

- Fixed all four sites (#61, #131, #205, #211) plus the lower-risk fifth instance in
  `ExpensesController`'s AI-extraction prefill the same finding flagged as worth doing alongside.
  Rode `#133` (an amount sanity ceiling, `MAX_AMOUNT = 100_000`) along in the same commit per the
  plan's explicit "cheap to add at the same time" note.
- A review pass found the fix correct at all sites with no false-positive risk (verified `amount`
  is always `positive` per `AmountValidation`'s own contract, so a real zero gross amount can't
  legitimately occur) and confirmed no existing caller plausibly needs an amount anywhere near the
  new ceiling. One gap found and fixed: the `ExpensesController` site was missing a regression test
  the other three each got (commit d771a616).
- Tier 0, 1, and 2 — everything money-safety-critical (double-payment risk, bank-detail/amount
  validation correctness) — are now complete and each independently reviewed. Continuing to Tier 3
  (job reliability & idempotency) next.

## Tier 3 (mailbox poll + AI-check reliability)

- **#4 (no idempotency key tying a created expense to its source message) — DEFERRED, not
  fixed.** Same class as the already-deferred #141: the real fix needs a new durable field (e.g.
  a `source_message_id` on the Expense record) plus retry-detection logic, which is a schema
  change, not a contained bug fix. The window this protects against is already narrow after the
  #84/#85 fixes below: `mark_read` is called immediately after `create_expense!` succeeds and is
  itself the guaranteed idempotency step (a message is never re-fetched once read), so the
  remaining exposure is only a crash between `create_expense!` returning and `mark_read` running —
  already surfaced loudly to Honeybadger with `duplicate_risk: true` rather than silently risking
  a duplicate. Left for a deliberate follow-up alongside #141 rather than rushing a schema change.

- Fixed together in one commit: **#39** (per-cost-centre poll loop had no isolation — a
  `poll_cost_centre_safely` wrapper now rescues+reports per cost centre so one mailbox's Graph
  outage can't stop the others being polled that cycle), **#84** (`mark_read_and_move` reordered
  to move-then-mark_read, so a move failure on the reject path — no expense created yet — leaves
  the message unread and safely retried, instead of the reverse order which could silently strand
  a read-but-unfiled message forever), and **#85** (`finalise_created` now runs attach and reply as
  separate best-effort steps, with the move-to-Processed gated on attach succeeding — an attach
  failure no longer swallows the reply the submitter is waiting on, and a partially-attached draft
  stays visible in the Inbox as a manual-follow-up signal rather than being filed away looking
  identical to a full success).

- **#183 (AiChecker sent the raw, short-lived Airtable attachment URL straight to Gemini)**: fixed
  by downloading the receipt bytes ourselves (new `http:` injection seam, defaulting to the shared
  `HttpTransport`) and building `RubyLLM::Attachment`s from them, mirroring the pattern `Extractor`
  and `BatchProcessor` already use instead of ever handing a remote fetcher a signed Airtable URL
  that might expire before it's fetched.

- **#12 (no concurrency guard on AiCheckJob)** was already fixed on this branch before this
  session's plan existed (commit `6d21f3c5`, dated before this execution plan was written) — no
  action needed, confirmed still in place.

- **#40 + #208 (AiChecker never raises, so a transient Gemini blip becomes a permanent lockout)**
  and **#75 (the idempotency guard also defeats retry of the Turbo broadcast)**: fixed all three
  together, same root cause — the guard conflated "a verdict was written" with "the expense was
  actually checked." Added `Expense#ai_checked?` (true only for a genuine `pass`/`fail` verdict,
  false for `error`) and used it in both `AiCheckJob`'s own idempotency guard and
  `ReviewController#kick_ai_checks`, so an expense stuck on `error` gets automatically rechecked
  the next time Review loads rather than being locked out forever. For #75, wrapped
  `broadcast_verdict` in its own rescue: a broadcast failure is a live-UI nicety failing, not a
  correctness issue (the next page load renders the true status straight from the store anyway),
  so it's logged + reported rather than allowed to trigger a job retry that the (now-correct)
  idempotency guard would just no-op on. Did **not** change `AiChecker` itself to raise on
  failure — its "never raises" contract is deliberate (its own doc comment: "so the Review queue
  keeps working") and is relied on elsewhere; reworking that felt like a bigger, riskier change
  than this finding needed.

- **#5 (three `limits_concurrency` calls default to a 3-minute lock TTL)**: added an explicit
  `duration:` to all four reimbursements jobs with a concurrency guard (the three the finding
  named, plus `AiCheckJob`'s guard for the same reason — RubyLLM's 120s `request_timeout` plus its
  own retries can plausibly exceed 3 minutes on a single Gemini call too). Sized generously rather
  than trying to derive an exact worst-case: 30 minutes for the batch jobs (per-expense SharePoint
  uploads + a Graph draft, up to a 200-row batch), 15 minutes for the mailbox poll, 10 minutes for
  the single-expense AI check.

- **#194 (GraphClient token not memoized per job run)**: fixed by memoizing `graph_builder.call`
  itself (`@graph ||=`) in `BuildBatchJob` and `NightlyBatchJob`, mirroring the `@store ||=`
  pattern both jobs already use — each job calls `graph_builder.call` at two-plus call sites per
  run (processor + notifier; reminder notify + issue/ready notify), each previously minting a
  fresh `GraphClient` and a fresh OAuth token fetch. Added a regression test per job proving the
  builder fires only once even when multiple call sites fire in one run (confirmed this already
  happens today with a single cost centre — not just a dormant multi-cost-centre concern).

- **#207 (mailbox poll's per-cost-centre MailboxClient token not memoized) — DEFERRED, not
  fixed.** Unlike #194, `MailboxClient` legitimately needs a fresh instance per cost centre (each
  wraps a different `receive_mailbox`), so instance-level memoization doesn't apply here — the
  real fix needs the OAuth token itself shared across instances (e.g. a `Rails.cache`-backed token
  cache in `GraphAuth`, mirroring the existing per-mailbox folder-id cache). That's a real change
  to shared auth plumbing, and would need cache-reset handling added to every test file building a
  real `MailboxClient`/`GraphClient` (mirroring the existing `Rails.cache.delete_matched
  ("reimbursements/graph-folder/*")` pattern already needed for folder ids) — bigger than the
  "cheap, do opportunistically" framing this finding started with. Also genuinely dormant today:
  `CostCentre.all.each` has exactly one iteration with only one cost centre configured, so
  `mailbox_builder.call` only runs once per poll cycle right now regardless. Left for a follow-up
  alongside Tier 5's other same-caveat cost-centre findings (#41/#80/#117).

- **#65 + #142 + #187 (nightly-run "send and record aren't atomic")**: fixed #65 and #187
  directly. `notify` now returns true (sent, or deliberately skipped because no operator
  recipients are configured — a config gap, not a delivery failure) or false (a send was attempted
  and failed); `handle_issues`/`alert_ready` only call `record_nightly_run!` when `notify` returned
  true, so a genuinely failed alert is retried the next due day instead of being silently recorded
  as handled and lost forever. `record_nightly_run!` is now called through a `record_run` wrapper
  that rescues its own failure (a DB blip) so it can't propagate into `run_for`'s outer rescue and
  trigger a spurious second "FAILED" email on top of an alert that already sent successfully. Did
  **not** separately fix #142 (a crash between a successful send and `record_run`'s commit still
  re-sends the identical alert next day) — same reasoning as the already-deferred #141: the residual
  window is now a single local DB write with no I/O of its own following a successful external call,
  genuinely narrow, and the alert in question is an internal operator nudge (not a payment), so a
  rare duplicate is a low-severity nuisance rather than a money-safety issue.

- **#168 (remind_stale_pending has no dedup key of its own) — reviewed, no fix needed.** Unlike
  #203, this path is DELIBERATELY meant to nag daily until the stale item is resolved (re-evaluated
  fresh each due day from current data), and it already only fires once per due day via the same
  `nightly_due?` gate every other outcome uses — adding a persisted "already reminded" dedup would
  actively work against the daily-nag design, not fix a bug. Left as-is.

- **#203 (CredentialsCheckJob has no dedup on the daily secret-expiry warning)**: fixed with the
  same `Rails.cache`-backed once-daily dedup `MailboxPollJob#alert_auth_failure` already uses —
  guards against Solid Queue's recurring-task catch-up enqueueing more than one run for the same
  day, or an operator manually re-triggering the job, either of which would otherwise resend the
  identical warning same-day.

- **#222 (only MailboxPollJob escalates GraphAuth::AuthError to IT)**: extracted the escalation
  logic MailboxPollJob already had into a new shared `Reimbursements::GraphAuthAlert.notify(error,
  source:)` (one shared dedup cache key across all three jobs — a credential failure hit by more
  than one job in the same cycle now sends a single email, not one per job) and wired it into both
  `NightlyBatchJob#notify` and `BuildBatchJob#notify`/`#perform` (the latter needed a rescue at both
  the notify step AND the outer `perform` body, since `BatchProcessor#process`'s own SharePoint/
  Graph-draft calls can raise `AuthError` before `notify` is ever reached). On an auth failure,
  these jobs now skip the (equally doomed) operator email entirely rather than attempting it.

- Fixing #222 surfaced a real jscpd duplication: adding the same `fail_with:` parameter to both
  jobs' near-identical test `FakeNotifier` doubles tipped them over the zero-duplication gate —
  consolidated both into one shared `ReimbursementsTestHelpers::FakeNotifier` (covering the union of
  methods both jobs' real `Notifier` calls: `pending_reminder`/`manual_review`/`approved_ready`/
  `batch_ready`/`failure`). This happens to close Tier 7's already-planned #46 finding as a
  byproduct, not something separately scheduled here.

- **Housekeeping note**: discovered mid-tier that my own manual `bash scripts/run-jscpd.sh <file
  list>` sanity checks between edits were silent no-ops all session — the script's positional arg
  is a jscpd `-f <formats>` filter (e.g. `ruby,erb,...`), not a file list, so passing file paths
  there ran `jscpd . -f "<first file path>"`, matched zero files, and always trivially reported "0
  clones." The REAL gate (hk's pre-commit step, invoked correctly via `git commit` every time this
  session) was never affected and did catch real duplication (e.g. this exact FakeNotifier case,
  and the two "fail_update_record_when helper" cases earlier in the session) — so no already-made
  commit is unverified. Going forward this session, the correct manual invocation is
  `bash scripts/run-jscpd.sh ruby,erb,javascript,typescript,css,scss,sass,vue` (whole-repo scan, no
  file-path arguments).

- **Tier 3 (job reliability & idempotency) is now complete.** Every finding in its four groups
  (mailbox poll, concurrency/timing, nightly-run alerting, token/client reuse) is either fixed,
  deliberately deferred with reasoning (#4, #207, #142), or reviewed and found not to need a change
  (#168, #12 pre-existing). Continuing to Tier 4 (security hardening) next.

- **Independent review of the full Tier 3 diff** (`git diff f45b7d96..003b2f12`) found one real
  ordering bug and flagged two accepted trade-offs worth documenting honestly:
  - **Fixed**: `CredentialsCheckJob#perform` had `Honeybadger.event` inside the `Rails.cache.fetch`
    dedup block, unlike `GraphAuthAlert`'s established pattern (Honeybadger fires unconditionally,
    only the email itself is deduped) — if Honeybadger raised after a successful `deliver_now`, the
    dedup key would never get cached and the retried job would resend the identical warning.
    Reordered to match `GraphAuthAlert`.
  - **Documented, not changed**: `MailboxClient#mark_read_and_move`'s move-then-mark_read reorder
    (the #84 fix) trades the "read-but-unfiled-in-Inbox-forever" failure mode for a narrower
    symmetric one (move succeeds, mark_read fails → unread-but-filed-in-Rejected/Processed,
    invisible to both the Inbox retry path and anyone watching that folder). Accepted: both need a
    Graph call to fail in the same narrow single-request gap, and the fixed failure mode (silent
    reprocessing risk) was worse than the one left. Comment updated to state this honestly instead
    of claiming a pure improvement.
  - **Documented, not changed**: the #208 recheck-on-error fix (`Expense#ai_checked?`) and the #12
    concurrency guard have a real, narrow interaction — if two enqueues for the same expense race
    while the first is erroring, the second (unblocked once the first's lock frees) does NOT no-op
    the way it would for a genuine pass/fail verdict, so it re-runs the check. This is the intended
    trade-off of allowing a recheck at all; the cost is bounded to one extra Gemini call in a
    narrow race, not a money-safety or data-integrity issue. Class doc + concurrency comment
    updated to state this precisely instead of implying an unconditional "no duplicate Gemini call"
    guarantee.

## Tier 4 (security hardening)

- **#150 (bank details missing from filter_parameter_logging)**: fixed — added `:sort_code`,
  `:account_number` to the allow-list (partial matching also covers the `_override` variants).
  One-line fix, done regardless per the plan's own note.

- **#111 (fence-forgery regex only matches ASCII dashes)**: fixed — `PromptSafety::FENCE_LOOKALIKE`
  now matches a set of dash-like Unicode homoglyphs (em/en dash, fullwidth hyphen, box-drawing bar,
  etc.), not just `-`. Verified the regression test actually catches the bug by reverting the fix
  and confirming the Unicode-dash test (and only that one) failed.

- **#108 (payee name unfenced in the AI-check prompt)**: fixed — wrapped in `PromptSafety.fence`
  like every other untrusted field in the same prompt.

- **#59 (receipt image/PDF itself has no prompt-injection defense)**: fixed at the shared
  `PromptSafety::UNTRUSTED_PREAMBLE` level (both `Extractor` and `AiChecker` interpolate it), adding
  an explicit paragraph telling the model the attached receipt is equally untrusted and any
  instruction-like text visible in the image is data to flag, not a command to obey. A receipt
  image can't be wrapped in a text fence, so this is a standing instruction rather than a fence.

- **#66 (no magic-byte verification on receipt uploads)**: fixed with a new shared
  `Reimbursements::ReceiptContentType` (Marcel-based sniffing, mirroring the pattern the app's
  `Attachment` model already uses) wired into all six receipt-intake call sites: `ExpenseForm`,
  `ExpensesController#extract`, `ExpenseEditsController#add_receipts`,
  `ReviewController#add_receipts`, `ReceiptsController#attach_uploads`, and
  `MailboxPollJob#usable_receipts`. Did **not** do the Tier-7-flagged dedup of the near-identical
  `add_receipts`/`attach_uploads` blocks themselves — same fix applied at each site's existing
  content_type check, consistent with keeping this a contained security fix rather than a
  refactor. Three existing tests asserted the OLD (declared-type-only) behavior using a real PDF
  fixture mislabeled with a wrong Content-Type header — that's no longer a meaningful "bad file"
  scenario once actual bytes are trusted over the label, so those tests were rewritten against a
  new `disguised_executable.pdf` fixture (real executable magic bytes, `.pdf` filename, PDF
  declared type) that represents the actual attack this finding cares about.

- **#95 (SharePoint drive_id/folder_id never re-verified before saving)**: fixed —
  `SettingsController#save_folder` now re-verifies a submitted drive_id against
  `graph.list_drives` for the cost centre's own configured site, and the folder_id by confirming
  `graph.list_folder_contents` resolves it (a wrong/nonexistent item 404s), before persisting.
  Refuses with a flash message rather than silently accepting a tampered hidden-field value.

- **#29 (inbound email producer-attribution has no throttle, no SPF/DKIM/DMARC check)**: split the
  finding's two halves. **Fixed**: a per-sender daily message cap (`MAX_MESSAGES_PER_SENDER_PER_DAY
  = 30`, a `Rails.cache`-backed counter) in `MailboxPollJob`, so a compromised/spoofed known-sender
  address can't mint unbounded Draft expenses under a real payee's identity or starve other
  senders out of a poll cycle's page size — over-limit senders get a reply pointing at the portal
  and are moved to Rejected, same pattern as the other reject paths. **Deferred, not fixed**:
  SPF/DKIM/DMARC verification via Graph's `internetMessageHeaders`/`Authentication-Results` header.
  This needs (a) requesting a new field in the Graph `$select`, (b) a parser for a
  vendor-specific, loosely-standardized header format I have no real captured samples to verify
  against, and (c) a design decision about what to actually do on a failed check (hard-reject vs.
  flag-for-extra-scrutiny) — a genuinely bigger, riskier change to build and verify blind (unlike
  the other Tier 4 fixes, which are all self-contained and fully covered by fake-based tests) than
  this pass warranted. Flag if you want this done as a dedicated follow-up with real Graph header
  samples to test against.

- **Independent review of the Tier 4 diff** (`git diff fc9aca50..8986c0ac`) found two real bugs,
  both fixed:
  - **Rate-limit retry inflation**: `sender_over_daily_limit?` incremented the per-sender counter
    on every `process(message)` call, but a message left unread by a downstream failure (e.g. an
    Airtable blip inside `create_expense!`) gets reprocessed every subsequent poll cycle until it
    succeeds — inflating one real email into many against the sender's tally, and risking a
    legitimate sender getting rate-limited for a transient failure that was never theirs. Fixed by
    caching the count a given message id was first seen at (`Rails.cache.fetch` keyed on
    `message.id`), so a retried message is only ever counted once. Verified by reverting the fix
    and confirming a new regression test (3 retries → count of 3 instead of 1) failed exactly as
    predicted.
  - **Inconsistent size-vs-content-type check ordering**: three of the five migrated `#66` call
    sites were reordered to check file size before the (now full-file-reading) content-type sniff,
    but `ExpenseForm#receipts_valid` and `ReceiptsController#attach_uploads` were left checking
    content-type first — meaning an oversized upload still gets fully read into memory before ever
    being rejected for size. Reordered both to match the other three sites. Added a regression test
    for `ExpenseForm` using a fake file object whose `.read` raises, proving the oversized branch
    never reaches the sniff at all.

- **Tier 4 (security hardening) is now complete** except for #29's deferred SPF/DKIM/DMARC half.
  Continuing to Tier 5 (cost-centre data-model gap) next.

## Tier 5 (cost-centre data-model gap)

- **#41 (BuildBatchJob has no cost-centre scoping), #80 (remind_stale_pending runs
  cost-centre-unscoped), #118 (reconciliation matchers never check cost_centre), #214 (reopen's
  stale-draft cleanup hardcodes the default mailbox) — ALL FOUR DEFERRED, not fixed. This is a hard
  blocker, not a scope judgment call**: every one of these needs `Expense`/`Budget`/`Batch` to carry
  a cost-centre link, but those three models are Airtable-backed records, not ActiveRecord — adding
  a field to them means adding an actual column/link field to the real Airtable base's Expenses/
  Budgets/Batches tables via Airtable's own UI or admin API, then wiring the resulting field id into
  `Reimbursements::Airtable::Config`/`FIELD_IDS`. I have no credentials or access to modify the
  production (or even a shared dev) Airtable base's schema from this environment, and inventing a
  placeholder field id would silently break in production the moment this ships (a field id that
  doesn't exist just resolves to `nil`, per the existing schema-drift-guard design — this would fail
  the same way an accidentally-renamed field does, just introduced deliberately instead of by
  drift). This needs a human with Airtable admin access to add the field first; I've left all four
  findings unfixed rather than build against a field id that can't exist yet. **This is the one
  Tier in the plan I can't execute autonomously — flag when you're ready to add the Airtable field
  and I can wire up all four fixes in one pass.**

- **#117 (CostCentre#eusa_code/receive_mailbox/send_mailbox have no uniqueness validation)**: fixed
  — this one IS self-contained (`CostCentre` is a normal ActiveRecord model in the app's own MySQL
  DB, unlike Expense/Budget/Batch). Added `uniqueness: true` for `eusa_code`, case-insensitive
  uniqueness for both mailboxes (matching how email addresses are already treated elsewhere in this
  diff, e.g. `MailboxClient` downcasing `from_address`).

## Tier 6 (data validation completeness)

- **#49 (Budget name/nominal_code presence) + #50 (budget_type inclusion)**: `Budget` is an
  Airtable-backed PORO like `Expense`, not ActiveRecord, so this couldn't be a model-level
  `validates` — added inline validation in `BudgetsController#update` (mirroring the existing
  `forecast` action's own inline-validate-then-redirect-with-alert style, since this controller has
  no form object). Added `Budget::TYPES = %w[Expense Income]` as the source of truth (previously
  only inline in the edit view's `select_tag`) and pointed the view at it too.

- **#71 (CostCentre email fields have no format check)**: added `URI::MailTo::EMAIL_REGEXP` format
  validation to `receive_mailbox`/`send_mailbox` (required) and `eusa_recipient` (optional,
  `allow_blank: true`) — the same validator `Opportunity`/`User` already use elsewhere in the app.
  `SettingsController#save_settings` already handled model validation failures gracefully (renders
  `:edit` with a flash), so no controller change was needed for this one.

- **#86 (Build Batch's free-text EUSA-recipient override has no email-format check)**: added the
  same format check to `BatchesController#create`, mirroring the existing BACS-date validation
  pattern exactly (validate before enqueuing; re-render `:new` with a flash on failure). Blank is
  still allowed (falls back to the cost centre's own, now format-validated, configured recipient).

- **#144 (submitted link-field ids aren't checked to resolve to a real record before writing)**:
  added `budget_record_id_error`/`owner_ids_error` to the shared `FinanceController` base (using
  `store.find_budget`/`store.find_person` against the already-cached lists, so this costs zero extra
  Airtable API calls) and wired them into the three call sites the finding named:
  `ReviewController#save`, `ExpenseEditsController#update` (both `budget_record_id`), and
  `BudgetsController#update` (`owner_ids`). Previously a stale/tampered id would reach
  `Store#update_expense!`/`#update_budget!`'s plain field-hash PATCH and only fail once Airtable's
  own API rejected the unknown linked-record id — surfacing as an unhandled 500 rather than a
  flash pointing at what to fix.

- **#151 (nominal_code uniqueness across budgets) skipped per the plan** — budgets intentionally
  share a nominal code (one code, several per-show budgets), not a bug.

- **Tier 6 (data validation completeness) is now complete.** Continuing to Tier 7 (consolidation/
  duplication cleanup) next — though most of it is mechanical refactor work with no user-facing
  behavior change; will scan it and decide whether it's worth doing in this pass or better left as
  a dedicated follow-up given the size of the diff already accumulated this session.

- **Independent review of the Tier 5+6 diff** (`git diff d2bc6ffa..3a0e225f`) found no bugs across
  all 7 checked angles (owner_ids_error input correctness, attrs-vs-params ordering, CostCentre
  self-uniqueness on resave — verified live, not just inferred — case-insensitive mailbox
  uniqueness, `URI::MailTo::EMAIL_REGEXP` strictness against real EUSA-style addresses, the
  batches_controller param-name consistency between validation and the enqueue call, and test
  fidelity). Clean pass, no follow-up needed.

## Tier 7 (consolidation / duplication cleanup) — controller seams onto FinanceController

- **19c (`checker_builder`/`modulus_checker`, 3 copies) + 19d (`notifier_builder`/`notifier`, 2
  copies) + 19e (`graph_builder`, 3 copies — 2 controllers + one already-separate job) + 19f
  (`find_expense!`, 2 copies) + #219 (generalized 19f into `find_or_404`, covering `find_expense!`,
  `find_budget`, `find_batch`, `find_person` — 8 call sites total once budgets/batches/people are
  included) + #215 (pagination one-liner, 4 copies)**: all six hoisted onto `FinanceController` in
  one pass, exactly as the plan's suggested PR boundary describes. `find_expense!` is kept as a
  thin `find_or_404(:find_expense!)` wrapper specifically so the 9 existing bare `find_expense!`
  call sites in `ReviewController`/`ExpenseEditsController` needed zero changes — only the
  duplicate private-method bodies were removed. Pure refactor, no behavior change: the full
  reimbursements suite has the exact same run count (733) before and after, all green.
- Did not touch `BuildBatchJob`/`NightlyBatchJob`'s own `graph_builder` (a job concern, already
  fixed for OAuth-token reuse in Tier 3's #194) — 19e's "3 copies" count includes that job alongside
  the two controllers; only the two controller copies were in scope for this controller-base
  consolidation.
- The remaining Tier 7 items (view/email partial dedup, service-layer dedup — especially #185/#224
  which flags the date/decimal-parse copies have already silently diverged, i.e. there's a real bug
  hiding in that duplication — and test-double dedup) are larger, higher-regression-risk refactors
  (changing shared view partials touches rendered HTML across many pages) — left for a dedicated
  follow-up pass rather than folding into this session's already-large diff.

## Tier 7 continued — job seams + log/Honeybadger boilerplate

- **#44 (`store_builder`/`store`, up to 4 copies)**: hoisted onto a new `Reimbursements::ApplicationJob
  < ::ApplicationJob` base class, inherited by `MailboxPollJob`/`NightlyBatchJob`/`BuildBatchJob`/
  `AiCheckJob` (the four that actually shared it — `CredentialsCheckJob` never touched the store, so
  left it on plain `ApplicationJob` rather than an unjustified change). `AiCheckJob#perform` also
  switched from a local `store = store_builder.call` variable to the inherited memoized `store`
  method, for consistency with the other three. `graph_builder`/`notifier_builder` were deliberately
  NOT hoisted onto this job base — they're each shared by only 2 of the 5 jobs (not all 4+), and
  BuildBatchJob/NightlyBatchJob's own per-job memoization there already has its own Tier-3 rationale
  (OAuth-token reuse per run) documented in place.

- **#52 + #190 (log + Honeybadger boilerplate, 10 sites across 6 files, both jobs and controllers)**:
  extracted into `Reimbursements::ErrorReporting#log_and_notify(message, error, context:)`
  (`app/services/reimbursements/error_reporting.rb`, alongside `GraphAuth` — the closest existing
  precedent in this codebase for a module mixed into more than one layer), included into both
  `Reimbursements::ApplicationJob` and `FinanceController`. Deliberately did NOT touch the
  `GraphAuth::AuthError` rescue clauses that call `GraphAuthAlert.notify` instead (Tier 3's #222
  fix) — those are a distinct, more specific escalation path, not the generic pattern this
  consolidates.
- **Caught a real bug via the full-suite run, not the per-file runs**: `FinanceController`
  (`Admin::Reimbursements::FinanceController`) is in a DIFFERENT namespace than
  `::Reimbursements::ErrorReporting` — `Admin::Reimbursements` and top-level `Reimbursements` only
  share a name segment, they are not the same module. A bare `include ErrorReporting` inside
  `FinanceController` raised `NameError: uninitialized constant
  Admin::Reimbursements::FinanceController::ErrorReporting` the moment any controller test loaded
  it (212 errors on the first full-suite run after adding it). Fixed with the explicit
  `include ::Reimbursements::ErrorReporting` the rest of this file already used for every other
  cross-namespace reference (`::Reimbursements::ModulusCheck`, etc.) — I'd simply missed doing the
  same for this one new line. `Reimbursements::ApplicationJob`'s own `include ErrorReporting` needed
  no such qualification, since that class genuinely lives inside the `Reimbursements` module.
  Reinforces why the full suite (not just the touched controller's own test file) has to run before
  every commit — a per-file run of, say, `settings_controller_test.rb` alone would have caught this
  too (every FinanceController subclass loads the same file), but this was still the first time the
  full suite ran after the change, and it caught it immediately as intended.
- Pure refactor otherwise: full suite run count unchanged (733) before and after, all green.

- **Independent review of this commit caught a second, subtler instance of the exact same
  lexical-shadowing hazard the FinanceController fix above already hit — this time silent, no
  NameError to surface it.** `CredentialsCheckJob < ApplicationJob` has zero diff in the commit (I
  never touched that file), but its ACTUAL superclass silently changed anyway: Ruby resolves a bare
  `ApplicationJob` reference via lexical nesting before falling back to the top-level constant, and
  once `Reimbursements::ApplicationJob` exists, that lexical lookup finds it first for every class
  in the `Reimbursements` module — including ones the commit never edited. Confirmed via
  `CredentialsCheckJob.superclass` before/after. Harmless today (the new base class only adds
  unused `store_builder`/`store` and `ErrorReporting` to a job that touches neither), but a latent
  hazard: any future `around_perform`/retry-policy addition to `Reimbursements::ApplicationJob`
  meant only for the 4 consolidated jobs would silently also apply here, with no diff to review it
  against. Fixed by making `CredentialsCheckJob < ::ApplicationJob` explicit (fully top-level
  qualified) with a comment explaining why, restoring the original, intended inheritance.

## Tier 8 (accessibility sweep) — first batch

- **#10 + #26 (missing `aria-live`)**: added `aria-live="polite"` to `_ai_verdict.html.erb`'s
  wrapper div (the AiCheckJob Turbo Stream replace target) and `settings/edit.html.erb`'s
  `#access_check_results` div. No visible rendering change (confirmed — an ARIA attribute has no
  visual effect), so no vischeck was run for these two; herb-lint + the existing controller test
  suites covering these pages are the verification.
- **#16 + #48 + #96 + #216 (missing `scope="col"`)**: added to every `<th>` across the 7 email
  templates (#16) plus `batches/new.html.erb`, `batches/show.html.erb`, `reconcile/preview.html.erb`
  (#48), and `budgets/edit.html.erb`'s forecast-log table (#96/#216) — one consistent pattern,
  applied everywhere it recurs per the plan's own instruction.
- **#34 (label `for` mismatch, Owners multi-select)**: verified live via `bin/rails runner` that
  `select_tag "owner_ids[]"` really does render `id="owner_ids_"` (Rails strips `[]` into a
  trailing underscore) before fixing — `label_tag :owner_ids` was pointing at a nonexistent
  `owner_ids` id. Fixed to `label_tag "owner_ids_"`. Added a regression test
  (`assert_select "label[for=owner_ids_]"` + `assert_select "select#owner_ids_[multiple]"`) since
  this is a genuine behavioral fix (label-click-to-focus, screen-reader association), not a
  no-op attribute addition.
- Rode along with #34 in the same file/edit: wired the "Ctrl/Cmd-click to select more than one"
  hint text to the select via `aria-describedby` (the same fix #153 asks for elsewhere) — cheap to
  do at the same time since I was already touching this exact label/select pair.
- Verified: `bundle exec herb lint` clean on all 13 touched files, full relevant controller/mailer
  test suites green, jscpd clean.

## Tier 8 continued — labels, hint wiring, disabled-button reason

- **#11 (reject-reason field, no label)** and **#35 (receipt file input, no label)**: both are
  per-record controls repeated once per expense card on a multi-record page, so a plain
  `<label for>` would collide across cards (duplicate ids) — used a record-scoped `aria-label`
  instead (`"Reason for rejecting expense #123"` / `"Attach receipts to expense #123"`), the same
  approach the plan's #116 entry recommends for exactly this class of control. The single-record
  `expense_edits/edit.html.erb` copy of the receipt field got a plain static `aria-label` (no
  scoping needed there).
- **#47 (bank-details error not wired via aria-describedby/aria-invalid/role=alert) + #70 (disabled
  button's reason only in a title tooltip)**: fixed in `people/index.html.erb`. The error `<p>` is
  now `role="alert"` with an id both fields reference via `aria-describedby`, and both get
  `aria-invalid` when there's an error. The verify button's disabled-reason moved from `title` to a
  visible sibling `<span>` wired via `aria-describedby`.
- **Caught a real bug via vischeck, not just herb-lint**: my first pass assigned the `error_id`
  local variable *inside* the `form_with do...end` block, then referenced it again after the block
  ended — Ruby block scoping means a variable first assigned inside a block doesn't leak to the
  surrounding template scope, so the page raised `NameError: undefined local variable or method
  'error_id'` the moment any row was expanded. herb-lint (a static ERB linter) has no way to catch
  this — it's a Ruby runtime scoping bug, not a markup error. Caught by `screenshot` +
  `Read`ing the resulting error-page image per the vischeck skill, before ever touching a browser
  manually. Fixed by moving the `error_id =` assignment above the `form_with` block. Also
  strengthened the existing `"invalid bank details re-render the form..."` test with assertions on
  the new `role=alert`/`aria-describedby`/`aria-invalid` markup, so this exact class of bug is now
  caught by the test suite too, not just a manual screenshot.
- Verified the disabled-button hint visually via `playwright-cli` (expanded a real no-bank-details
  row): renders as gray `text-xs` text next to the grayed-out button, matching the surrounding
  house style, no layout regressions.

## Tier 8 continued — decorative glyphs (#76, #221)

- Wrapped every decorative Unicode glyph (`←`, `→`, `↑`, `📁`, `⚠️`) in `<span aria-hidden="true">`
  across `settings/edit.html.erb` and `settings/_folder_picker.html.erb`, converting each from a
  plain string `link_to` into block form so the glyph could be isolated from the link text.
- **Verified against real, live SharePoint data** (this dev environment has genuine Graph
  credentials configured for the Fringe cost centre) via `playwright-cli`, not just a screenshot:
  drove the actual folder picker — browsed into the real "Documents" library, into a real
  "Bedlam Fringe 2026" folder, and back up — and read the accessibility snapshot at each step.
  Confirmed the accessible name of each link excludes the glyph (`link "Documents"`, `link
  ".Trash-1000"`, `link "Up one level"`) while the visible text still shows it (`text: → Documents`,
  `text: 📁 .Trash-1000`) — exactly the intended behavior, not just "no visible change" but a
  positive confirmation the ARIA fix does what it claims against real data. Two console messages
  seen during this were pre-existing and unrelated (a broken external logo image URL, an unused
  CSS-preload warning).
- Added a regression test asserting the "← All cost centres" link's glyph span carries
  `aria-hidden="true"`.
