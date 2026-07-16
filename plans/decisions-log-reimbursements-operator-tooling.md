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
