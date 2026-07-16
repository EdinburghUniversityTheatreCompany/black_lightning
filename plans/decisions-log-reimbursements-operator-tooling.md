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

- **#1 (BACS spreadsheet 32-row overflow)** — not yet reached this session, continuing after this
  log entry.
