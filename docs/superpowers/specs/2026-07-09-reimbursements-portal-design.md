# Reimbursements Portal — Design

**Date:** 2026-07-09
**Status:** Approved (Mick, 2026-07-09)
**Target:** MVP shipped by the weekend of 2026-07-11/12, running alongside the existing Airtable form for Fringe 2026.

## Context

Bedlam Fringe expense submissions currently go through a public Airtable form and are
processed by the operator-only `bedlam-bacs` Streamlit app (sibling repo), which reviews
them, runs an AI check (Gemini), builds BACS batches for EUSA, and reconciles payments.
Submitters (producers) have no authenticated surface: they can't see the status of their
expenses, VAT receipts are often missing, and every submission is typed by hand into a
long form.

This feature gives producers a portal inside Black Lightning (they already have EUTC
accounts here) to:

1. **See their own expenses and statuses** (Pending / Approved / Submitted / Paid / Rejected, incl. rejection reasons and AI-check comments).
2. **Submit expenses receipt-first**: upload a receipt, Gemini extracts sensible defaults, they confirm a prefilled form. Missing VAT itemisation is a *soft* block.
3. **Email receipts** to `reimbursements@bedlamfringe.co.uk`; the app links them to the sender's account, creates a draft-quality Pending expense, and replies (including an "address not recognised" reply for unknown senders).

The old Airtable form stays live as a fallback; **the Airtable base schema is not
changed**. `bedlam-bacs` is untouched and remains the operator/review/batch tool.

Ultimate direction (out of scope now, but shapes naming): Black Lightning handles both
termtime and Fringe payments as two cost centres with different budgets and admins, and
a budget-owner approval step precedes finance-admin processing.

## Decisions (settled with Mick)

- **Stack:** build in Black Lightning (Rails 8.1). Astro/new app rejected — this is an authenticated CRUD app and BL already owns identity (Devise), roles (CanCanCan+Rolify), uploads (ActiveStorage), and mail (ActionMailer).
- **Source of truth:** the existing Airtable base, accessed directly via the Airtable REST API with **field IDs** (same convention as bedlam-bacs). No local mirror, no sync, no Airtable schema changes.
- **Caching is a hard requirement:** Airtable free plan allows ~1,000 API calls/month per workspace, shared with bedlam-bacs. Aggressive Solid Cache caching; a typical portal visit must cost 0 Airtable calls.
- **Identity link:** match BL user → Airtable People record by email on first touch; persist the match in a new nullable `users.airtable_person_id` column.
- **Email-in transport:** poll a new M365 shared mailbox via Microsoft Graph (app-only client-credentials auth) from a recurring Solid Queue job. No ActionMailbox/MX changes.
- **Email-in gaps:** create the Pending expense with as much filled in as the AI can confidently extract (including a suggested payment reference per the guidance below); leave unknown fields blank; the reply asks the submitter to complete it in the portal. Portal forms keep all required fields required.
- **Deferred:** budget-owner approval step (needs a new status = Airtable schema change), termtime cost centre (config entry later), replacing the Airtable form, migrating bedlam-bacs into Rails.

## Architecture

```
Producer ──login (Devise)──▶ Black Lightning /reimbursements
                                   │ read/write (field IDs, cached)
                                   ▼
                             Airtable base  ◀── existing Airtable form (unchanged)
                                   ▲
                                   │ review / batch / reconcile (unchanged)
                             bedlam-bacs (operator)

reimbursements@bedlamfringe.co.uk (M365 shared mailbox)
        ▲ reply / move            │ poll every 5 min (Graph, app-only)
        └──────── Solid Queue job ┘ → Gemini extraction → Airtable create
```

### Components (all namespaced `Reimbursements::`)

1. **`Airtable::Client`** (`app/services/airtable/client.rb`)
   - Thin Faraday/Net::HTTP wrapper over the Airtable REST API: list records (with pagination), get, create, update, and attachment upload via the `uploadAttachment` content endpoint (base64, ≤5 MB/request; receipts are comfortably under).
   - All reads/writes use **field IDs**, never names (mirrors bedlam-bacs so Airtable column renames break neither app).
   - Base ID, table IDs, and field IDs live in **Rails credentials** (encrypted, committed — repo may be public; IDs are identifiers, not secrets, but this keeps them tidy). The Airtable PAT is a secret: Kamal secrets / env. Field IDs are documented in bedlam-bacs' `config/field_ids.example.toml`; copy the real values from Mick's `config/field_ids.toml`.
   - Honours 429s with retry-after; raises typed errors.

2. **PORO models** (`app/models/reimbursements/`) — `Expense`, `Person`, `Budget`, `Attachment`; plain Ruby objects hydrated from Airtable records, mirroring bedlam-bacs' dataclasses. `Expense` exposes the same status enum (`Pending → Approved → Submitted → Paid`, `Rejected` terminal) and the payee-override "effective" semantics. No ActiveRecord.

3. **`Reimbursements::Store`** (cache-fronted repository)
   - The only thing controllers/jobs talk to; wraps `Airtable::Client` with Solid Cache:
     - **Budgets** (active list): TTL 1 h.
     - **People** (full list, keyed for by-email lookup): TTL 1 h; busted on person create/update.
     - **Expenses** (full list, one global key): TTL 10 min; filtered per person in Ruby, so one API call serves every portal visitor per window; busted on any portal write; manual "Refresh" button busts on demand.
   - Budget math: a submission = ~2–3 calls (create + attachment upload(s)); a poll cycle with no new mail = 0 Airtable calls.

4. **Cost-centre config** (`Reimbursements::CostCentre`) — small frozen config with one entry ("Fringe 2026" → this base + mailbox + portal copy). Termtime later = one more entry, not a rewrite.

5. **`Reimbursements::Extractor`** (Gemini)
   - `gemini-2.5-flash` via the Gemini REST API (`GEMINI_API_KEY` env — same key bedlam-bacs uses), multimodal input (PDF/JPEG/PNG/WEBP receipt bytes), **structured JSON output**:
     `{merchant, purchase_date, total_amount, vat_amount, vat_itemised (bool), currency, suggested_description, suggested_budget (from provided live budget list, nullable), suggested_payment_reference (≤18 chars), confidence_notes}`.
   - Payment-reference guidance in the prompt mirrors the form copy: prefer an invoice-specified reference, else invoice number, else `<merchant/purpose> <surname>` truncated to 18 chars.
   - Never raises to callers: errors return an "extraction unavailable" result and the form simply starts blank.

6. **Portal UI** (`app/controllers/reimbursements/…`, ViewComponents, Turbo, Tailwind — BL conventions)
   - Routes under `/reimbursements`, behind `authenticate_user!`. Any signed-in member may use it; data is scoped to their linked People record. No new Rolify role.
   - **My expenses**: status badges, amounts, budget, rejection reason, AI comment, receipt filenames. Expenses created via email-in with gaps get a "needs completion" banner. Manual refresh button.
   - **New expense** (receipt-first): upload receipt(s) (ActiveStorage direct upload) → Turbo-updated prefilled form ← Extractor result → user reviews/edits → submit.
   - **Edit** own expense **only while Pending** (completes email-in drafts, fixes mistakes). No cancel/delete — copy says contact finance@.
   - **My payment details**: name, sort code, account number (format-validated: 6/8 digits) writing to their People record; shown/prompted when missing, since bedlam-bacs gates approval on bank details.
   - **First visit**: email-match against People → store `airtable_person_id` on the user. No match → they can still submit; a People record is created on first submission from their BL name/email.

7. **Validation (portal form)** — all Airtable-form-required fields stay required: budget, type, amount, amount excl VAT, description, ≥1 receipt, payment reference. Extra checks: amount > 0; amount excl VAT ≤ amount; payment reference live 18-char counter + truncation warning; sort-code/account format on invoice payee overrides.
   - **VAT soft-block:** if the extractor reports `vat_itemised: false` (or amount excl VAT == amount on a non-exempt-looking receipt), show a warning explaining that only the ex-VAT amount leaves their budget and asking them to tick "I understand — I'll ask for a VAT invoice where possible" before submitting. Never a hard block.

8. **Submission writer** — creates the Airtable Expense record (status Pending, submitter linked, all fields via field IDs), uploads receipts to the attachment field, busts the expense cache, then purges the temporary ActiveStorage blobs (receipts live in Airtable/SharePoint as today; no duplicate copy in Wasabi).

9. **Email-in** (`Reimbursements::MailboxPollJob`, recurring every 5 min via Solid Queue `config/recurring.yml`)
   - **Graph client** (`app/services/reimbursements/graph_client.rb`): app-only client-credentials token (`AZURE_TENANT_ID` / new app registration client id+secret), list unread messages in the shared mailbox, download attachments, send replies from the same address, move messages to `Processed` / `Rejected` folders. Idempotency: only unread + moved-after-processing; a processed message is never re-read.
   - **Unknown sender** (no People match, cached lookup) → reply: address not recognised; register/submit via the portal link or contact finance@. Move to `Rejected`.
   - **Known sender, no usable attachment** → reply asking for the receipt as a PDF/photo attachment. Move to `Rejected`.
   - **Known sender + attachment(s)** → Extractor over attachments (+ subject/body as context) → create **one Pending expense per email** with everything confidently extracted (amount, amount excl VAT if itemised, description from subject/merchant, suggested budget if confident, suggested payment reference); blanks where unsure → attach receipts → reply summarising what was captured with an edit link ("please check budget and payment reference in the portal") → move to `Processed`.
   - Failures (Graph/Airtable/Gemini down): job logs + Honeybadger; message stays unread and is retried next cycle; replies are sent at most once per message (reply happens immediately before the move, and the move is the commit point).

### One Rails migration

`add_column :users, :airtable_person_id, :string, null: true` — the only schema change anywhere.

## Error handling

- Airtable 429/5xx: retry with backoff in the client; portal shows stale cache with a "data may be a few minutes old" note rather than erroring.
- Gemini failure: form falls back to blank manual entry (feature-degrades, never blocks submission); email-in falls back to "attachment received, please complete in the portal".
- Graph failure: poll job no-ops and retries next cycle; Honeybadger notification on repeated failures.
- Cache-bust discipline: every write path goes through `Reimbursements::Store`, which owns invalidation.

## Testing

Minitest per BL conventions (webmock-stubbed HTTP for Airtable/Gemini/Graph; factories for users):

- `Airtable::Client`: field-ID payload translation, pagination, attachment upload, 429 handling.
- `Store`: cache hit/miss/bust behaviour (0-call reads on warm cache).
- `Extractor`: prompt assembly + JSON parsing incl. malformed-response fallback.
- Controllers/system: auth gating, scoping to own expenses only, prefill flow, VAT soft-block acknowledgement, required-field validation, Pending-only editing.
- `MailboxPollJob`: unknown sender, no attachment, happy path, idempotency (already-moved message), partial extraction with blanks.

## Manual setup checklist (Mick, ~15 min)

1. Create shared mailbox `reimbursements@bedlamfringe.co.uk` in the M365 tenant.
2. New Azure app registration: application permissions `Mail.ReadWrite` + `Mail.Send`, admin consent, client secret.
3. `New-ApplicationAccessPolicy` scoping the app to only that mailbox.
4. Create `Processed` and `Rejected` folders in the mailbox.
5. Provide: tenant id, client id/secret, Airtable PAT, Gemini key → Kamal secrets / `.env`.
6. Copy real table/field IDs from bedlam-bacs `config/field_ids.toml` into Rails credentials.

## Out of scope (deferred, designed-for)

- Budget-owner approval step (requires a new status → Airtable schema change + role/notification flow).
- Termtime cost centre (add a `CostCentre` config entry + its base/budgets when ready).
- Retiring the Airtable form; migrating bedlam-bacs review/batch/reconcile into Rails.

## Related quick wins (separate from this build, logged in bedlam-bacs `plans/off-topic-improvements.md`)

- Add VAT-itemisation check to bedlam-bacs' AI checker prompt (covers Airtable-form submissions).
- "You've been paid" email at Reconcile time.
- Duplicate-submission warning (same amount + merchant within 30 days) at review.
