# Round review findings (2026-07-25)

Review of `f7521eb7..dce7a826` (63 commits, 167 files) by four parallel reviewers.
Status key: **FIX** = must land before deploy · **DEFER** = backlog · **REJECT** = pushed back on.

## Reviewer 1: finance-logic correctness — REPORTED

### Critical

1. **FIX — `eusa_actual_amount` is linkage-only, so unmatched EUSA spend on a *budgeted*
   nominal code is invisible everywhere.** `app/models/reimbursements/budget.rb:188`
   (`debit_actual_total`) counts only debits on actuals linked to one of that budget's
   expenses; `DatabaseStore#unbudgeted_actuals` (`database_store.rb:93`) excludes any actual
   whose nominal code matches *any* budget. An unlinked debit on a budgeted code is in
   neither. £1,250 of real spend can sit on the ledger with the overview showing £0 for that
   budget *and* "No unbudgeted spend". Same shape for income via `credit_actual_total:179`.
2. **FIX — credits never reduce an expense budget's EUSA actual, so refunds overstate spend.**
   `debit_actual_total` sums debits only, and `ReconcileController#match_credit_to_budget:169`
   offers credits to *income* budgets only. A £300 supplier refund on an expense code can
   never attach to that budget: the budget keeps reading £900 when the true net is £600, and
   `expected_outturn` inherits it. Also swallows year-end accrual reversals.
3. **FIX — the overview grand total adds income budgets to expense budgets.**
   `budgets_controller.rb:39` builds `NominalCodeRollup.new(nil, store.budgets)` over both
   types with no sign inversion or type filter, and `overview.html.erb` has no Type column
   (the budgets index does). £10k spend + £8k income = £18k, which is neither total spend nor
   net. Not caught by tests because the overview test's income budget has no `initial_budget`
   and a blank nominal code.

### Important

4. **FIX — unticking one of two byte-identical offsetting pairs offsets both.**
   `Reconciliation::OffsetPair#key` (`reconciliation.rb:29`) is a content digest, and
   `ReconcileController` selects by key, so duplicate rows collapse to one key — defeating the
   index-based protection its own `rows_outside` comment promises. Reviewer reproduced:
   two identical £10 DR + two identical £10 CR → `distinct keys: 1 of 2`. Also emits duplicate
   DOM ids so the second `label_tag` targets the first checkbox. **No route exists to
   un-offset a pair**, so a false positive is unrecoverable in the UI.
5. **FIX — pairs on *different* nominal codes clear the score floor on a shared reference.**
   ref(4) + period(1) + same-day(0 penalty) = 5 ≥ `OFFSET_MIN_SCORE` with zero nominal
   agreement. A Sage payment-run ref stamped across a run pairs £1,234.56 of lighting hire
   (041000) with £1,234.56 of ticket income (081000): both stamped offset, the expense behind
   the debit stays Submitted and its producer is never paid. Asymmetry argues for a hard
   same-nominal gate: a false positive hides real spend irrecoverably, a false negative just
   leaves rows visibly unmatched.
6. **FIX — `unbudgeted_actuals` includes offset legs and already-linked rows.** No
   `reject(&:offset?)`, no `expense_id`/`budget_id` exclusion (only `actuals_controller.rb:27`
   filters offsets). A correctly-offset £4,200 accrual pair is then reported as £4,200 of
   unplanned spend. Also: `coded` contains `""` when any budget has a blank nominal code,
   suppressing every blank-code actual.
7. **FIX — a malformed amount in a batch budget update is silently dropped.**
   `budget_updates_controller.rb:54,70` — `parse_decimal` rescues to nil and nil means "skip".
   `1,200` or `£1200` both raise. Flash says "5 forecasts logged" while the sixth budget keeps
   its superseded forecast. `ExpenseForm#parse_decimal` handles these formats; the two parsers
   disagree.
8. **FIX — the preview's "will mark N expenses Paid" understates after an untick.** `preview`
   computes matched debits from unpaired rows only; `apply` restores unticked legs and can pay
   (and email) more expenses than the confirmation promised. The suite documents this
   behaviour rather than flagging it.

### Minor
9. **DEFER — no financial-year scoping in any new rollup** (`database_store.rb:67,84,93`,
   `budget.rb:179,188`). Latent while one FY of data exists; the grand total silently doubles
   on the first day of the next FY. Also `create_actual!` stamps import-time FY while
   `detect_offsetting_pairs` derives FY from the row date.
10. **FIX — the Actuals export's Amount column is unsigned with no offset marker**, so summing
    a mixed export in Excel adds income to spend, and an included offset pair counts 2× rather
    than 0.
11. **FIX — partial write if an offsetting pair fails to cross-link**: both legs are persisted
    by separate `create_actual!` calls before `link_offsetting_pair!`, so a failure there
    leaves exactly the half-linked state that method's transaction exists to prevent.
12. **FIX (doc) — `OFFSET_MIN_SCORE`'s comment is wrong**: it claims a reference match alone
    clears the floor; ref alone is 4 − date penalty, so only a *same-day* ref match does.
    Finance reads the /8 score in the UI.

### Suspected (verify before fixing)
- Double conversion of one actual: `set_convertible_actual` checks then
  `create_expense!` + `link_actual_to_expense!` run unwrapped — a failure between them leaves
  a Paid expense with no back-link and a still-convertible row.
- Rows carrying both a debit and a credit bucket on `debit - credit`, so DR100/CR40 pairs with
  CR60 at score 8. Unconfirmed whether EUSA's export ever populates both on one row.
- From-EUSA conversions stamp `FinancialYear.current`, not the ledger row's year.

### Confirmed sound (coverage)
BACS builder unchanged apart from the `CellSanitizer` extraction (identical trigger list, row
cap, totals, text formats); From-EUSA expenses can't enter a batch or the review queue; VAT
field consistency across all new sums; subtotals reconcile exactly with rows and grand total;
nil/zero handling; no double-count between `paid_portal_amount` and `eusa_actual_amount` (max,
not sum); BigDecimal exactness in bucketing with no float anywhere; cross-cost-centre pairing
impossible; offset rows genuinely cannot be converted.

## Reviewer 2: security / data handling — REPORTED

### Important
S1. **FIX — `payee_name_override` ciphertext overflows its `varchar(255)` column.**
   `expense.rb:84` encrypts it; `db/schema.rb:787` is `t.string`. Reviewer measured the real
   encryptor: any low-redundancy plaintext ≥124 chars exceeds 255 bytes (255 chars → 398).
   Rails' own `validate_column_size` guard validates the **decrypted** value, so it never
   catches this. Invoice-mode AI prefill dropping a long payee line in → `ValueTooLong` → 500 on
   a path that worked before encryption; under non-strict MySQL it truncates and
   `support_unencrypted_data` then hands the truncated JSON back as "plaintext", putting
   `{"p":"AbC…` on the **BACS spreadsheet**. `docs/reimbursements/encryption-rollout.md:18`
   explicitly claims no migration is needed — that claim is false for this column.
S2. **FIX — outbound gating misses `upload_to_folder` and `delete_message`, the two Graph calls
   that carry bank details.** `batch_processor.rb:72-73` uploads the BACS xlsx and receipts
   *before* `create_draft:81`. A dev shell with fnox Azure creds clicking Build Batch PUTs a
   file of full sort codes and account numbers into **production** SharePoint, then the
   suppressed draft records a fake `suppressed-…` id while expenses flip to Submitted anyway.
   `reopen` can likewise `delete_message` a real draft from the live mailbox. Track B delivered
   "dev can't send mail", not "dev has no outbound side effects", and the ungated half is the
   half with the bank data.
S3. **FIX — the rollout runbook's verification step is a non-deterministic query that matches
   nothing.** `encryption-rollout.md:89` does `where.not(account_number: "")`; non-deterministic
   `encrypts` serialises the comparison with a fresh IV and Rails does not raise, so it returns
   nil and an operator reads that as "no plaintext rows left" — and that confirmation is the
   *only* gate on flipping `support_unencrypted_data = false`, after which un-backfilled rows
   raise on read. Confined to the doc: no application code queries these columns by value
   (grepped).
S4. **FIX — the Track K 404 swallow silently defeats `mark_read`'s deliberately-loud
   duplicate-risk path.** Exchange **changes a message id on move**, so a 404 can mean "moved,
   still unread", not "gone". `mailbox_poll_job`'s `mark_read_or_flag_duplicate` detects failure
   only by the raise, so: draft created, mark_read reports success, reply 404s so the sender is
   never told, move 404s, and nothing above `logger.info` fires. The email is silently
   abandoned. Also `move` wraps `folder_id` → `find_or_create_folder`, so a *folder*
   misconfiguration gets mislabelled "message gone". Narrow the rescue to the message-scoped
   request or re-GET to confirm it is really gone.

### Minor
S5. **FIX — a 51 KB `database_consistency_2026_07_25_08_20_26.txt` artifact was committed**
   (in Track I's `597784a3`), carrying absolute paths. Its contents also document that
   `database_consistency` now **crashes** on both newly-encrypted models
   (`can't add a new key into hash during iteration`, from Rails' encrypted-column length
   validation) — the step is advisory (`|| true`) so CI stayed green while coverage of those two
   models silently stopped. `config.active_record.encryption.validate_column_size = false` fixes
   that and removes the useless validation from S1.
S6. **FIX — the audit line masks the account number but writes the full sort code**
   (`people_controller.rb:132`), contradicting `Exports::People`, which masks both.
S7. **FIX (doc) — the backfill task's idempotency comment is wrong**: `#encrypt` re-encrypts
   unconditionally, so every run rewrites fresh ciphertext for every row.
S8. **DEFER (decision) — the People export carries every payee's name and email in the clear.**
   The masking rationale applies to those columns too; wants a deliberate call, not an omission.
S9. **FIX — `ai_checker.rb:166` puts `sort_code_override`/`account_number_override` verbatim
   into the Gemini prompt.** Pre-existing, but this round made *extraction* opt-in behind an
   explicit "Google may store and human-review this" disclosure while the finance-triggered
   check on the same expense still ships a third party's full bank details to the same
   free-tier endpoint with no notice to anyone. Strip them from the prompt.
S10. **FIX — a string `receipts[]` param 500s.** `expenses_controller.rb:105` — a String has
   `#size` so it passes the byte check, then `ReceiptContentType.allowed_upload?` calls `#read`
   → `NoMethodError` from any authenticated producer. Guard with `respond_to?(:read)`.

### Suspected
- `appended_notes` is a read-modify-write on the encrypted `notes`, so two concurrent
  bank-detail edits would lose an audit line. Not verified.

### Confirmed sound (coverage)
Authorization on every new route/export (all finance-gated; producer-only → 403 asserted);
masking holds in the only exporter with bank columns and the workbook reuses it so sheet and CSV
cannot drift; BACS still correctly carries full numbers; `CellSanitizer` covers every text cell
while leaving negatives numeric so amounts still sum; log/param filtering covers the trio plus
AR encryption's own filter registration, and Honeybadger inherits it; **the AI consent path is
sound** — no default mode so a modeless request 422s before reaching Gemini, self mode never
even asks for bank fields and the controller strips them anyway, radios reset on every new file
pick, override validation unweakened, prefill writes `.value` so no XSS; email-in really did stop
calling Gemini; dev key literals unreachable outside development; no plaintext secret newly
committed; 404s stay loud on the SharePoint upload path; nothing bypasses encryption via
`update_column`/`update_all`; `save_folder` re-verifies client-supplied drive/folder ids against
the cost centre's own site.

## Reviewer 4: test-quality adversary — REPORTED
(Each finding names the mutation that would keep the suite green — that is the proof of weakness.)

### Critical
T1. **FIX — the outbound gate's production branch is never exercised.** `test_helper.rb:35` sets
   `REIMBURSEMENTS_ENABLE_OUTBOUND=1` for the whole suite, so every test runs the opted-in path.
   **Mutation: delete `return true if Rails.env.production?` → suite green, and production
   silently stops sending every rejection/payment email, every mailbox reply, and every EUSA
   BACS draft** — with `create_draft` returning a fake `suppressed-…` id that `reopen` would
   treat as a real draft. `Rails.env` is assignable, so this is testable without mocks.
T2. **FIX — encryption has no coverage of the rollout paths**, only the post-`encrypts`
   round-trip. Untested: `support_unencrypted_data` letting a pre-existing plaintext row read
   (the single assumption the whole production rollout rests on), the backfill task, and a
   key-absent environment. **Mutation: flip `support_unencrypted_data` to false → suite green,
   every un-backfilled production row raises on the money path.**
T3. **FIX — Track J's actual payload is never driven in a browser.** `saveThenDecide`,
   `discardThenDecide` and `#injectEditFields` never execute in any test; the server tests
   hand-craft the flat params the JS is supposed to produce. **Mutation: drop the
   `save_changes` hidden input → suite green, every "Save Changes" click silently discards the
   operator's edits and decides on the un-edited claim — the exact bug the track exists to
   prevent.**
T4. **FIX — save-then-decide never proves the decision acts on the *saved* values.**
   **Mutation: return the stale expense object from `save_edits_before_decision` → all six
   tests pass.** Consequence: an owner-endorsed £30 claim edited to £3,000 via Save Changes is
   approved against the stale £30 endorsement, bypassing the re-endorsement rule.

### Important
T5. **FIX — offsetting-pair ticking is only ever tested with exactly one proposed pair.**
   Mutation `applied_pairs = ticked.any? ? pairs : []` stays green while an operator unticking
   one of three pairs gets all three collapsed. (Covered by the offset-safety fix agent.)
T6. **FIX — `rows_outside`'s duplicate-row hazard, named in its own comment, is untested.**
   `ActualsRow` is a `Data`, so value equality collapses duplicates; a paste containing the same
   charge twice loses one row entirely. (Covered by the offset-safety fix agent.)
T7. **FIX — the score floor is pinned from above but not below**: nothing scores 3, so
   `OFFSET_MIN_SCORE = 3` keeps the suite green. Same for `OFFSET_NEAR_DATE_DAYS` 31 → 1.
T8. **FIX — the Opportunity expiry fix shipped with no test** (my own fix). Reverting both
   comparisons to `Time.current` is green for 23 of 24 hours. A `travel_to` at 00:30 BST locks it.
T9. **FIX — the Airtable migration dropped `PersonLink`'s stale-link recovery branch.**
   Mutation: return early on a present stored FK instead of falling through to the email match →
   green, and a user whose payee row was deleted gets a **duplicate payee** created on their
   next submission.
T10. **FIX — store cache-bust coverage collapsed from ~12 tests to 2** across 22 `bust_*!` call
   sites. Removing `bust_budgets!` from `update_budget!` or `create_forecast!` stays green while
   any write-then-read request renders stale figures.

### Minor
T11. **FIX — the self-mode browser test can't tell which mode the JS posted** (its canned
   extraction carries no bank fields). Mutation: change the "self" radio's value to `"invoice"`
   → green, and a "reimburse myself" scan silently asks Gemini for bank details.
T12. **FIX — a test asserting only an always-rendered card title** (`budgets_controller_test.rb:341`);
   its neighbour asserts `"4000"`, which is the row's own nominal code, so only one subtotal
   actually pins the grouping.
T13. **DEFER — header assertions compare a constant against itself** in several export tests;
   renaming a column passes. Expenses headers are spelled out literally once, so the pattern is
   pinned there only.
T14. **DEFER — flakiness risks**: process-global ENV mutation in five files whose `ensure`
   restore is a no-op if `test_helper.rb:35` is ever removed; a monkeypatched
   `Extractor.new`; row-count assertions that break on any new fixture; and
   `review_decision_controller.js:29` calling `#serialize` with no `hasEditFormTarget` guard,
   plus an unescaped `name=value` join so a description containing `&`/`=` can defeat the dirty
   check.

### Assessed and sound
The ~10 tests rewritten onto unpersisted AR models do **not** assert against their own stubs —
in each case the stubbed reader is *input* to the logic under test and the real reader is
covered elsewhere. The removed Airtable schema-drift, importer and backup-copy tests are
correctly gone. The real losses are T9 and T10.

## Reviewer 3: Rails architecture — REPORTED
(Measured real query counts with read-only scripts inside rolled-back transactions.)

### Important
R1. **FIX — "Discard Changes" can silently SAVE the edits it promised to discard.**
   `review_decision_controller.js` — `#injectEditFields` strips stale `[data-injected-edit]`
   inputs but `discardThenDecide` → `#submitPending` does no cleanup, so fields left by an
   aborted save survive into the discard submission. Reachable: edit → Approve (override, which
   always carries `data-turbo-confirm`) → Save Changes (injects fields, `requestSubmit()` fires
   the confirm) → Cancel the SweetAlert (Turbo aborts, DOM keeps the inputs) → Approve again →
   Discard Changes → the discarded edit is committed. → routed to the test-coverage agent.
R2. **FIX — `expenses` never preloads `person: :payment_details`**, so
   `ReviewSupport.attention_summary` → `effective_has_bank_details?` costs one query per payee.
   Measured 10 extra queries for a 10-payee export; +150 for an end-of-year workbook.
   → routed to the budget agent (same file).
R3. **FIX — a stale/bogus budget id in a batch budget update 500s** instead of flashing:
   raw `params[:amounts]` keys go straight to `create_budget_update!` and
   `BudgetForecast belongs_to :budget` is required. Reproduced. `budget_record_id_error` exists
   and is not called. → budget agent.
R4. **FIX — the batch-update form discards every typed amount on any error** (both failure
   branches redirect, and the form renders each amount field with a hard-coded nil). → budget agent.
R5. **FIX — pair application is not atomic** (three separate writes); worse, **re-pasting cannot
   repair it** because `dedup` then skips the already-imported leg, so the pair can never be
   re-formed. Confirms finance finding 11. → offset agent.
R6. **FIX — actual→expense conversion is not atomic**; a failed link leaves a Paid expense plus
   a still-convertible row, so the next click double-counts. Confirms the suspected race. → offset agent.
R7. **FIX — "Unbudgeted spend" lists offset noise and credit rows** under copy that calls them
   "real spend no one planned for". Confirms finance findings 1/6. → budget agent.
R8. **FIX — the committed `database_consistency` artifact** also proves the encryption change
   *crashes* that checker for both encrypted models. Confirms S5. → security agent.
R9. **FIX — `store.budgets` now loads the whole actuals ledger on every producer page.** Track G
   added the actuals preload to the *shared* reader, so `active_budgets` — used only to draw a
   `<select>` — instantiates the entire expenses table plus their actuals (measured 6 queries for
   a dropdown). Needs a separate overview-only reader. → budget agent.

### Minor
R10. **FIX — dead references left by the Airtable deletion**: eight model/service comments still
   name `Reimbursements::Airtable::*` classes that no longer exist; `database_store.rb:190`
   references "the Airtable store"; `Attachment` documents an Airtable era. Worse,
   **two fallbacks are now dead AND broken**: `ai_checker.rb:63` and `batch_processor.rb:161`
   both do `receipt.bytes || download(receipt.url)`, but `wrap_receipt` always passes a blob so
   `bytes` is never nil — and if reached they would fail, because `url` is now a path-only
   `rails_blob_path` that `URI()` cannot fetch. Also `supports_message_idempotency? = true` is a
   permanently-true two-backend seam.
R11. **DECIDE — `index_reimbursements_eusa_actuals_on_reconciliation_status` is never used** (all
   offset filtering is in Ruby). Drop it or add a scope that uses it. → offset agent.
R12. **DEFER — `request.query_parameters.merge(format: :csv)` into path helpers in six views**
   means `:anchor`/`:script_name`/`:params` are interpreted as routing options. Pre-existing
   pattern now extended; an explicit allow-list of each page's filter keys would be safer.
R13. **FIX — `Exports::Base#checker` is optional in the base but mandatory in two subclasses**, so
   `Workbook.new(store:)` NoMethodErrors on the first payee with bank details. → offset agent.
R14. **NOTE — the atomicity claim on `create_budget_update!` can't be asserted from a functional
   test**: a bare `.transaction` joins Rails' per-test transaction, so the inner rollback is a
   no-op. Reviewer reproduced. Use `requires_new: true` or assert elsewhere. → budget agent.
R15. **FIX — dialog polish**: no `aria-labelledby`, so screen readers announce an unnamed dialog;
   native Escape bypasses `#cancel()` leaving `#pendingForm` set (the same field R1 turns on).
   → test-coverage agent.
R16. **FIX — a blank nominal code counts as "coded"** in `unbudgeted_actuals`. Confirms. → budget agent.
R17. **FIX — the two hardest dialog paths have no browser coverage.** Confirms T3. → test agent.
R18. **FIX (docs) — CLAUDE.md documents four tracks but not the two most operationally
   dangerous**: Track F's encryption (per-env keys, dev fallback literals,
   `support_unencrypted_data = true` as an unfinished follow-up, the backfill task) and
   `Settings.outbound_enabled?`, which makes `MailboxPollJob` a total no-op and silences every
   send outside production. Both will bite whoever next wonders why email-in does nothing
   locally. → coordinator (me), after the fix agents land.

### Suspected
- A suppressed `create_draft` returns a fake `suppressed-…` id that `BatchProcessor` persists;
  `reopen` requires Graph to confirm the draft is unsent, so a dev/staging batch may be
  permanently un-reopenable. (Overlaps S2 — the security agent is deciding that return contract.)
- `notes` headroom under encryption: `text(65535)`, envelope roughly doubles bytes, and
  `appended_notes` appends an audit line per change forever. Not measured.
- Consent radios can't be re-triggered: the scan fires on radio `change`, which won't re-fire if
  the same option is re-selected, so a poor reading can't be re-scanned without re-picking the file.

### Clean dimensions (coverage)
All three migrations correct (legacy integer-PK FK rule honoured, self-referential FK split with
a real `down`, schema version and every annotation current); the budget-overview preloads are
genuinely effective (**8 queries for the whole page, constant in budget count**) and the
`loaded?` guard in `debit_actual_total` does what it claims; the exports abstraction earns its
keep (107-line base, five real subclasses, one HEADERS + one `#row` driving both formats, adding
a column is a two-line change — not a god object) and `CellSanitizer.cell`'s type-preserving
branch is right; **merge-resolution integrity verified across all five conflict-touched files** —
nothing lost or duplicated; Rails idiom sound on the new read paths (CSV never kicks AI jobs,
proper 404s, `unprocessable_entity` on form failures, mode whitelist with 422, URL-as-state
preserved); no *silent* Airtable-era behaviour change — each is commented, documented and tested.
