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
