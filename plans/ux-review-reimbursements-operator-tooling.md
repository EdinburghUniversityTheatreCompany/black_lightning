# UX Review — Reimbursements Portal (2026-07-16/17)

Four persona-based review agents walked the live app in a real browser (Playwright +
screenshots), each judging against ten shared criteria: action clarity, state visibility,
timing, flow continuity, terminology, error recovery, confirmation for consequential
actions, consistency, empty/loading/async states, and trust for financial info.

Personas: **receipt submitter** (first-time student producer, likely on a phone),
**finance administrator — daily review/edit work**, **finance administrator —
budgets/batching/reconciliation**, **finance administrator — infrequent settings/setup
(non-technical treasurer)**. A fifth persona — the **budget owner** — turned out to have
no surface in the app at all; see the feature proposal at the end.

Seeds from Mick (pre-confirmed, excluded from agents' reports but included in the plan
below): (a) the "Save Draft" button on the new-expense form doesn't make clear the other
button fully submits, and the draft/submit boundary is generally crossed silently;
(b) the bank-detail override fields being collapsible hides whether they're filled in —
should not be collapsible.

Test-data side effects to clean up in Airtable (the app has no delete UI for any of
these): expense #29 flipped Pending→Approved (Mick checked, OK), test expenses #32
(Approved, £50) and #33 (Pending, £999,999,999), payment details "Claude Dev"
(20-20-20 / 55779911) on the dev user's person record, and a Budget Forecast entry
(£941.31, "UX review test entry - Claude") on a real budget — the forecast one matters
most since it skews that budget's Current Forecast/Remaining/Variance rollups.

---

## P0 — Broken functionality (fix first; these aren't UX polish, they're outages)

### P0.1 Reconcile flow is dead in a real browser
`ReconcileController#preview` (and `#apply`'s success path) `render` directly instead of
redirecting; Turbo Drive rejects non-redirect form responses ("Form responses must
redirect to another location") and silently discards them. Clicking "Parse and match"
does nothing — no error, no navigation. Server-side logic is fine (verified via curl).
The entire paste-reconciliation workflow is unusable through the UI, and Step 3 (Apply)
is unreachable. Fix: redirect-with-re-derivable-state, or make the flow a Turbo Frame.
(Related to the existing `turbo-stream-redirect-gotcha` project memory.)

### P0.2 Validation failures on 422 re-renders are completely silent
On the Settings form, a rejected save (invalid mailbox; the new empty-run-days
validation) sets `flash.now[:alert]` and renders 422 — the flash payload is embedded in
the response but the SweetAlert pipeline (waiting on `turbo:load`) never fires for
in-place 422 renders, only redirects. The page redraws with **zero** indication the save
failed. Likely affects every `flash.now[:alert]` + 422 path in the section (Review save
errors, Batches create errors, Budgets update errors, Reconcile apply errors) — audit
all of them. Fix: hook the flash renderer on `turbo:render` as well, or render errors
inline in the form.
Note: this also explains why functional tests could only assert those flashes via
`response.body` and never via the `flash` accessor.

### P0.3 Build Batch is an invisible background job
The Build Batch page reads as synchronous, but `create` enqueues `BuildBatchJob` and
redirects with a one-time flash. History has no "building…" row; a pre-draft failure
writes NO Batch record at all — the only failure signal is an email to whoever clicked.
An operator (or a colleague) cannot tell in-app whether a build is mid-flight, failed,
or never happened. Fix: write an attempt/status record at job start (building /
complete / failed + error) and render it on History with a persistent colored state.

### P0.4 Producer pages 500 on a slow Airtable response
A `Net::OpenTimeout` during the post-save expenses refetch produced a raw error page
right after saving bank details (the most trust-sensitive moment for the submitter);
production would show a generic 500. No rescue exists in the producer-facing
controllers for `Airtable::Error`/timeouts. Fix: rescue in
`Admin::Reimbursements::BaseController`, serve stale cache with an inline "couldn't
refresh just now — your changes were saved" notice.

---

## P1 — Money-safety and trust (the review's core theme)

### P1.1 Approve has no confirmation — single or bulk — while Reject always confirms
Reject carries `turbo_confirm` ("…and email the producer? This can't be undone.");
Approve has none, even on a card flagged "Needs attention" (over budget / possible
duplicate are advisory-only and never block). Bulk is worse: "Select all" ticks flagged
cards indistinguishably and "Approve selected" fires with no confirm at all (the bulk
Reject already has a dynamic one). Fix: confirm on Approve whenever the card has
attention reasons (naming them); bulk-Approve confirm summarising how many selected are
flagged and why.

### P1.2 "Needs attention" conflates hard blocks with advisories, hides its reasons, and cries wolf
Three distinct findings, one badge:
- Hard-blocked reasons (no bank details / no budget / no ex-VAT) and advisory-only ones
  (over budget / no receipt / possible duplicate) render identically — an operator can't
  tell which flagged rows will actually reject their Approve.
- The reason list is behind a click (popover) on every page; render it inline on Pending
  cards (it's short) — same class as the collapsible-overrides seed.
- The badge fires on Paid/Submitted rows in the Expenses table (11 of 26 rows), training
  the eye to skip it. Suppress or restyle for non-actionable statuses.

### P1.3 The draft/submit boundary is crossed silently in both directions (extends Mick's seed)
- New form: "Save Draft" vs the submit button — the distinction isn't explained (seed).
- Edit page of a Draft: the button says "Save changes" but actually promotes
  Draft→Pending (verified live: it landed in the finance queue).
- Edit page of a Pending: "Save as draft" silently *withdraws* a live claim from the
  finance queue with no warning.
- No explicit "Delete draft" or "Withdraw claim" exists anywhere; withdrawal is an
  unlabeled side effect.
Fix as one cluster: state-aware button labels ("Submit expense" / "Withdraw back to
draft" with confirm), a line of copy above the buttons stating the current state and
what each button does, and explicit Delete-draft / Withdraw-claim actions.

### P1.4 The uploaded receipt is silently lost on a validation error
Submit with any other field invalid → 422 re-render → file input is empty (unavoidable)
but nothing says so; after fixing the other fields the browser blocks with "Please
select one or more files." The single most likely first-time stumble. Fix: inline error
on the receipt field after a failed create ("Please re-attach your receipt — uploads
don't survive a failed submit"); longer-term, use the edit page's immediate-upload
dropzone pattern on the new form.

### P1.5 No upper sanity bound on amounts
£999,999,999 sails through into the finance queue. The realistic error is typing pence
as pounds. Fix: soft-block above a threshold (~£1,000) with an acknowledgement checkbox,
mirroring the VAT soft-block pattern.

### P1.6 Budgets page: contradictory signals and inverted colors
- "Over budget" badge computed against `initial_budget` while Remaining/Variance are
  forecast-based rollups → red badge next to "Variance: £0.00", or next to positive
  Remaining. Align the baselines or label them.
- Variance color is inverted: negative (good) is red, positive (over) is unstyled.
- Negative Remaining — the one unambiguous "over" number — gets no styling at all.

### P1.7 Bank-detail overrides should not be collapsible (Mick's seed)
Filled-in override state is invisible while collapsed. Render the three fields inline
(always visible), with a filled/empty visual state.

### P1.8 Settings safety gaps (beyond P0.2)
- The run-days hint still says "Leave all unchecked to never auto-submit" — now
  contradicted by the validation added this session (#193/#229). Update the copy.
- "SharePoint set"/"Configured" badges ignore `sharepoint_site_url` — all-green with a
  blank or repointed site URL. Make `sharepoint_configured?` (or the badge) require it.
- Changing receive/send mailbox or a SharePoint folder has no consequence warning and
  no confirm on replacing an already-configured folder.
- "EUSA recipient" — the address the BACS email actually goes to — has no hint text.
- Build Batch's "Body (HTML)" textarea passes raw HTML into the real EUSA draft and (in
  dev) leaks Rails view-annotation comments into the editable text. Add a rendered
  preview; strip annotation comments defensively.

---

## P2 — Clarity and communication

- **Status vocabulary**: no legend/tooltips; "Submitted" is both a status (= batched to
  EUSA) and a date column header (= created); "Pending" answers the system's question,
  not the producer's ("when do I get paid?"). Add badge tooltips, rename the column,
  consider producer-facing aliases (Waiting for review / With EUSA / Paid).
- **"EUSA" is never expanded** on any producer page. Expand on first use per page:
  "the Students' Association (EUSA)".
- **Producers lose all access after the editable window**: no show view exists — can't
  re-view their claim or their own receipts. Add a read-only show page.
- **Bank-details state is invisible once set** — the only signal is the warning banner's
  absence. Add "Payments go to your account ending 9911 — change" strip on the index.
- **AI verdict gaps** (finance): the explanation (`ai_comment`) renders only on the
  Review page — Submitted/Paid expenses show a bare "AI: Fail" pill with no reason on
  the edit page (add the comment box there); a pass-with-suggestion renders in the same
  green box as a plain pass and gets ignored (style distinctly and/or add an "apply
  suggested budget" affordance).
- **"Missing" bank details renders neutral gray** in People while equally-blocking
  "Invalid" is red. Make Missing a danger/warning color.
- **Error copy leaks attribute names** ("Budget record", "Amount excl vat",
  "Vat acknowledged") — add activemodel attribute translations.
- **Required-field stars don't match reality**: Budget/Description/Payment reference are
  required to submit but unstarred (draft-only optionality). Star them; the draft button
  already uses formnovalidate.
- **Status-page failure copy tells non-technical users to "check the Airtable PAT /
  Azure credentials"** — things with no UI surface. Point at the escalation path
  ("contact the development team / IT") instead.
- **VAT acknowledgement checkbox label isn't clickable** — the
  `tailwind_horizontal_boolean` SimpleForm wrapper emits a `<label>` with no `for`,
  app-wide. Fix the wrapper (associates label ↔ input); this is also an a11y defect.
- **Microsoft-access setup collapsible** needs one bolded line: "These steps need
  Microsoft 365 admin permissions — if that's not you, hand this section to IT."

## P3 — Polish / nits

- Mobile: page-title `<h1>` collapses to zero width at 390px (flex child needs
  `min-w-0 truncate`).
- Blocked-edit message (good copy) renders as a red "Oops…" error modal — route via
  `flash[:warning]`, not `alert:`.
- Success toasts auto-dismiss in 4.5s with no durable trace (acceptable for expenses —
  the new row is the trace — fold bank details into the P2 status strip).
- Batch history shows two identical unlabeled dates (name vs date_sent).
- Flash toast overlaps the breadcrumb.
- Budget owners field is a bare native multi-select (ctrl-click).
- "No owner" badge on 26/31 budgets (payroll lines will never have one) — suppress for
  overhead/hidden budgets.
- Batch show renders "EUSA draft created: no" as plain text — render false states as
  warning badges on index + show.
- No edit/delete for Budget Forecast entries (mistakes permanent app-side).
- Re-running access/status checks doesn't dim previous results.
- "Bacs folder" vs "BACS request folder" capitalization (`purpose.humanize`).
- Orphaned "Find an Expense" page — no link anywhere points to it; link it or remove it.
- Excl-VAT > gross amount renders unflagged (one real data row does this and single-
  handedly flips a budget over-budget).
- Receipt re-extraction JS overwrites user-corrected fields unconditionally (code-level;
  skip user-edited fields).

---

## Feature proposal: budget-owner review (Mick's request)

There is currently **no budget-owner surface at all** — Budgets pages are finance-gated,
so an owner who wants to see (let alone vet) spending against their budget must ask
finance. Mick's ask: budget owners should be able to review expenses submitted against
their budget, with the step bypassed when the submitter *is* the owner.

Sketch (needs a design pass before building):
- **Identity**: match the signed-in user to a People record (email), then to budgets via
  `owner_ids`. (Email-matching already exists for the producer portal's own expenses.)
- **Surface**: a "My budgets" page (base `access` permission, not finance) listing owned
  budgets with plain-language figures, and per-budget submitted expenses.
- **The review step**: an owner endorse/flag action on Pending expenses against their
  budget. Design decisions to make with Mick:
  - Blocking gate (finance can't approve until an owner endorses) vs advisory signal
    (a badge finance sees, like the AI check)? Advisory is far less disruptive to the
    existing money pipeline and mirrors the AI-verdict pattern; blocking changes the
    state machine and Airtable schema.
  - Bypass: auto-endorse when submitter's person record is among the budget's owners.
  - Multiple owners: any one owner's endorsement suffices?
  - Owner without a portal account: fall back to no gate, or email-based nudge?
  - Notification: email owners on new submissions against their budget?
- **Schema**: needs an `owner_endorsed`(+by/at) field on Expenses (Airtable change — the
  same blocker class as the deferred Tier 5 cost-centre link fields; note the planned
  MySQL migration may be the better moment).

## What worked well (keep these patterns)

Build Batch/Reopen's consequence-stating prose + scoped confirms with exact counts;
disabled-state explanations instead of mute grayed buttons; the payment-details error
copy ("Sort code must be 6 digits, e.g. 80-22-60."); the bank-details warning banner's
timing; the VAT explainer that teaches rather than gates; the stale-edit-link redirect
that explains instead of 404ing; the index intro sentences on each page.
