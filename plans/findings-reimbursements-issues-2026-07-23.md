# Reimbursements issue investigation — findings (2026-07-23)

Recovered from session `e48a6b27-9d5e-4e39-bb9f-145b19e31763` (ran 23:05–23:29 local in the
`.claude/worktrees/reimbursements-fixes` worktree). Ten subagents investigated; only two
results reached the coordinator before the session ended, so these are lifted verbatim from
the subagent transcripts. Nothing here has been re-verified.

---

## Investigate BACS payment reference

### Findings

I traced the BACS payment-reference value end-to-end and verified the generated xlsx against the real template cells. **The column→attribute mapping is correct and NOT swapped.** There is no code bug where a description is written into the PAYMENT REFERENCE column.

#### Exact column → attribute mapping (verified against the real xlsx)

I dumped the template's actual cells (`lib/reimbursements/templates/EUSA_BACS_template.xlsx`, sheet `BREAKDOWN`, row 1 headers / row 2 example):

| Col idx | Template header (row 1) | Example (row 2) | Code constant (`bacs_xlsx.rb`) | `BacsRow` field | Source attr (`batch_processor.rb#build_xlsx`) |
|--------|--------------------------|-----------------|-------------------------------|-----------------|-----------------------------------------------|
| 0 | PAYEE: | E X AMPLE | `COL_PAYEE=0` | `payee_name` | `expense.effective_payee_name` |
| 1 | AMOUNT £ | 250.57 | `COL_AMOUNT=1` | `amount` | `expense.amount` |
| 2 | SORT CODE (6 digits) | 202020 | `COL_SORT_CODE=2` | `sort_code` | `expense.effective_sort_code` |
| 3 | ACCOUNT NUMBER (8 digits) | 5050236 | `COL_ACCOUNT_NUMBER=3` | `account_number` | `expense.effective_account_number` |
| 4 | NOMINAL CODE | 439999 | `COL_NOMINAL_CODE=4` | `nominal_code` | `expense.effective_nominal_code` |
| 5 | COST CENTRE | F40 | `COL_COST_CENTRE=5` | `cost_centre` | `@cost_centre.eusa_code` |
| **6** | **PAYMENT REFERENCE (if required)** | **(blank)** | **`COL_PAYMENT_REFERENCE=6`** | **`payment_reference`** | **`expense.payment_reference`** |
| **7** | **DESCRIPTION OF EXPENSE/NOTES** | **TRAVEL EXPENSE RECLAIM** | **`COL_DESCRIPTION=7`** | **`description`** | **`expense.description`** |

- Constants: `app/services/reimbursements/bacs_xlsx.rb:36-43`
- Cell writes: `bacs_xlsx.rb:105` (`COL_PAYMENT_REFERENCE ← payment_reference`) and `:106` (`COL_DESCRIPTION ← description`)
- Row build: `app/services/reimbursements/batch_processor.rb:145` (`description: expense.description`) and `:146` (`payment_reference: expense.payment_reference`)

The template's own example row confirms the intended semantics: PAYMENT REFERENCE is left **blank** ("if required"), and the human-readable narrative ("TRAVEL EXPENSE RECLAIM") goes in DESCRIPTION. The code does exactly this. The existing test `test/services/reimbursements/bacs_xlsx_test.rb:28-29` asserts the same (`first[6]=="PROPS ALICE"`, `first[7]=="Fake blood"`). Git history shows the mapping has been correct since introduction (`2709f506`); the recent database-backend flip did not touch it.

#### Every write path for `payment_reference` — all produce a short reference

There is no path anywhere that stuffs a description into `payment_reference`:

1. `expense_form.rb:96` — submitter form; validated `length: { maximum: 18 }` (`REFERENCE_LIMIT`, line 18/34).
2. `extractor.rb:139` — AI prefill; truncated to 18 chars.
3. `mailbox_poll_job.rb:301` — email-in; uses `extraction.suggested_payment_reference` (already ≤18).
4. `review_controller.rb:234-236` — when blank, auto-fills via `ReviewSupport.auto_payment_reference(budget.name)` (BACS-safe, capped 18: `review_support.rb:28-30`).
5. `review_controller.rb:303` / `expense_edits_controller.rb:218` — manual operator edit.

`description` and `payment_reference` are separate DB columns on the AR model (`app/models/reimbursements/expense.rb:14,19`) and separate fields in the Airtable mapper (`airtable/mapper.rb:64,72`). No swap in the store layer either.

#### Why the reference "looks like a description" (the real cause)

Since the column mapping is correct, the value the user sees is genuinely whatever is stored in `expense.payment_reference` — and that is a **data/product issue, not a mapping bug**. The most likely source is the AI-suggested reference: the extractor prompt (`extractor.rb:106-108`) tells Gemini to fall back to *"a short `<merchant or purpose>` label"*, which produces prose-like snippets (e.g. "Amazon fake blood") that read like a mini-description — and email-in relies solely on that AI value. The field is capped at 18 chars, so it can't be a *full* description, but it can certainly read like one.

#### Proposed patch

I am **not** proposing a swap patch — that would break correct code. The columns are right, the test is right, and the template confirms it. If the desired behaviour is "the reference should be a crisp claim code, not an AI narrative," that is a semantic change and belongs in the reference-*generation* logic, not the xlsx builder. Two candidate changes (please confirm which behaviour you actually want before I implement):

- Tighten the extractor prompt so the fallback is a code, not prose — `app/services/reimbursements/extractor.rb:106-108`:
  - Before: `...otherwise use the invoice number; otherwise a short "<merchant or purpose>" label.`
  - After: `...otherwise use the invoice number; otherwise the merchant name only (no description of what was bought), max 18 chars.`
- Or make the default reference deterministic (e.g. `EUTC-<auto_number>` or budget-name based) rather than AI free text, changing `auto_payment_reference` / the extractor fallback.

Before I'd land either, I'd want confirmation of the intended reference format, because the current code is behaving as designed and as the template intends.

#### Test file for a regression test

`test/services/reimbursements/bacs_xlsx_test.rb` — the row-mapping assertions are at lines 22-33 and 108-118 (`first[6]` = payment reference, `first[7]` = description). That is where a column-mapping regression test would go. `BatchProcessor#build_xlsx`'s attribute wiring is not directly unit-tested for column mapping today; the closest integration coverage is the BacsXlsx test above.

---

## Audit bank-details permissions/security

Read-only audit complete. Here are the findings, ranked by severity.

### Reimbursements bank-details security audit

#### Data model recap
Bank details live in two plaintext locations:
- `reimbursements_payment_details.sort_code` / `.account_number` / `.notes` — the payee registry (`app/models/reimbursements/payment_details.rb:8-9`, one-per-`Person`).
- `reimbursements_expenses.sort_code_override` / `.account_number_override` / `.payee_name_override` — per-claim "pay a third party directly" overrides (`app/models/reimbursements/expense.rb:7,17,25`).

Two distinct CanCanCan gates:
- Producer portal (`BaseController`, `app/controllers/admin/reimbursements/base_controller.rb:38-40`): `:access, :reimbursements`, every action scoped to the caller's own `current_person`.
- Finance surfaces (`FinanceController`, `finance_controller.rb:34-36`): `:manage, :reimbursements_finance`. People registry, Review, and any-status expense edit all inherit this.

---

#### HIGH — Bank details stored unencrypted at rest
`sort_code`, `account_number` and the `notes` audit column are plain `string(255)`/`text` columns with no ActiveRecord Encryption (`payment_details.rb:8-9`; `person.rb:6-16` annotation). The same is true of the expense override trio (`expense.rb:7,17,25`). I grep'd the whole tree for `encrypts`/`attr_encrypted` — the only encryption in the app is Devise's `encrypted_password`; nothing touches these fields. Anyone with DB/backup/replica access reads full UK bank details in cleartext.

Made worse: `PeopleController#appended_notes` (`people_controller.rb:118-123`) writes the **full account number and sort code into the `notes` text column** on every change, so even if you encrypted the two dedicated columns, cleartext copies persist in `notes` (and `notes` is rendered on the People page, `people/index.html.erb:87`).

**Fix:** enable ActiveRecord Encryption.
1. `bin/rails db:encryption:init`, store the three keys in the production credentials (dev keys can be ENV/fnox per your dev-secrets-are-public rule).
2. `encrypts :sort_code, :account_number, :notes` on `Reimbursements::PaymentDetails`; `encrypts :sort_code_override, :account_number_override, :payee_name_override` on `Reimbursements::Expense`. Use **non-deterministic** (default) — no code queries these by value (modulus check and uniqueness operate on `person_id`/email, not the numbers), and `string(255)` easily holds the ciphertext for 8–12 chars.
3. Backfill: set `config.active_record.encryption.support_unencrypted_data = true`, then `Reimbursements::PaymentDetails.find_each(&:encrypt)` and same for expenses; flip the flag off once done.
4. Separately, stop embedding the full account number in the `notes` audit line (mask to last-4, or drop the number and keep just "bank details updated" + timestamp) so the audit trail doesn't reintroduce cleartext.

---

#### MEDIUM — No "who" attribution on bank-detail changes; no view audit
`appended_notes` records *what* changed and *when* but not the acting user — there's no `current_user` reference anywhere in `people_controller.rb`, and no logging when bank details are merely viewed. For financial-payee data you likely want per-change actor attribution and (optionally) a read-access log. **Fix:** include `current_user.id`/name in the audit line, or better, a proper `paper_trail`-style audit record instead of free-text in `notes`.

#### MEDIUM — Finance grant is coarse; all payees' details visible to any finance-role holder
`People#index` renders every payee's full sort code + account number in editable fields (`people/index.html.erb:46,54`), unmasked, to anyone with `:manage, :reimbursements_finance`. There is no per-record scoping here (correctly so — finance builds the BACS batch). This is by design, but it means the blast radius equals the membership of that one role. **Action (not a code fix):** confirm the `reimbursements_finance` role membership is tight, and consider last-4 masking with reveal-on-demand on the list view to reduce shoulder-surfing / accidental-screenshot exposure. `PermissionsController` should keep `reimbursements_finance` a deliberately-granted subject.

#### LOW — Airtable backend stores the same data in a third-party base
When `REIMBURSEMENTS_BACKEND=airtable` (production default until the flip per your CLAUDE.md), bank details also sit in a US-hosted free-plan Airtable base shared with bedlam-bacs. Data-residency/processor concern. Being retired by the MySQL cutover, so noting for completeness, not action.

---

#### Things I checked that are FINE — don't chase these
- **Log filtering is correct.** `config/initializers/filter_parameter_logging.rb:11` filters `:sort_code, :account_number`. Partial matching covers the finance form's `sort_code_override`/`account_number_override` (`expense_edits_controller.rb`) and the nested `reimbursements_payment_details_form[sort_code]` params. Verified against `test/filter_parameter_logging_test.rb`.
- **CSV export excludes bank details.** `ExpenseEditsController::CSV_HEADERS` (`expense_edits_controller.rb:149-150`) is #/Status/Payee/Budget/Amount/… — no sort code or account number. Good.
- **Emails don't leak bank details.** Grep of `app/views/reimbursements/emails/*` shows only "the money should reach your account shortly" phrasing; no numbers rendered.
- **The AI extraction JSON endpoint** (`expenses_controller.rb:161-175`) returns merchant/amount/description only — no payee bank fields.
- **Mass-assignment is scoped correctly.** Producer path `PaymentDetailsController#update` (`payment_details_controller.rb:23-27,33-35`) resolves the target via `person_link.ensure_person!(current_user)` — the record id comes from the session user, never params, so a producer cannot write another person's details. The any-status editor is finance-gated. No cross-user write path found.
- **Override write path validates + normalizes** and enforces all-or-nothing on the trio (`expense_edits_controller.rb:248-266`, `bank_details.rb:39-42`), so partial third-party splicing is blocked.

**Headline:** the one thing genuinely worth acting on is encryption at rest (HIGH) — everything on the access-control/exposure side is already sound. The audit-attribution gap is the reasonable second.

---

## Assess Gemini privacy + opt-in scan

I now have the complete picture. Here are my findings.

---

## Data-privacy investigation: Reimbursements receipt → Gemini extraction

### 1. What is sent to Gemini today, and when

**The entire raw receipt file is uploaded** — not OCR'd text, not a redacted subset. The actual PDF/image bytes go to Google.

- `app/services/reimbursements/extractor.rb:83-87` (`attachments`) wraps each receipt's raw `bytes` in a `RubyLLM::Attachment` (a `StringIO` of the file), filename carrying the extension so RubyLLM detects the MIME type. This is multimodal input: the model receives the whole picture/PDF (up to 5 MB, `ExpenseForm::MAX_RECEIPT_BYTES`), so **anything visible on the receipt is transmitted**, including fields the app never parses.
- The prompt (`extractor.rb:89-111`) additionally sends the **list of budget names + record IDs** (`budget_lines`). On the email-in path it also sends **free-text `context`** = the submitter's email subject/body (`extractor.rb:116-126`, fed by `mailbox_poll_job.rb:183`). The interactive portal path sends no claimant name in the prompt, but the receipt image itself may show it.
- Model: `gemini-2.5-flash` via RubyLLM (`extractor.rb:15`), configured globally in `config/initializers/ruby_llm.rb:13-16` with `config.gemini_api_key`.

**Two auto-send paths, both fire without a human pressing anything:**

1. **Interactive portal (the user's concern).** `app/views/admin/reimbursements/expenses/_form.html.erb:72` wires the file input to `action: "change->reimbursements-receipt#extract change->reimbursements-receipt#stash"`. The instant a file is selected, `reimbursements_receipt_controller.js:80-104` POSTs the file to the `extract` endpoint. The controller action `ExpensesController#extract` (`expenses_controller.rb:93-106`) reads the bytes into RAM (`receipt_payload`, line 157-159) and calls `extractor.extract`. **No button, no confirmation — extraction is automatic on upload.**
2. **Email-in.** `Reimbursements::MailboxPollJob` (recurring, every 5 min) runs Gemini extraction per new inbound message with an attachment (`mailbox_poll_job.rb:183`). Also fully automatic.

The extraction result is returned as JSON and used only to *prefill* form fields (`expenses_controller.rb:161-176`, JS `#fill` at `reimbursements_receipt_controller.js:134-156`). It is advisory — the user still confirms/edits every field. It never blocks: failures return `ok: false` and the form stays manual (`extractor.rb:6-8`, controller comment `expenses_controller.rb:89-92`).

### 2. Privacy analysis

**Sensitive data typically on these receipts, all transmitted whole:**
- Merchant, date/time, line items (line items can themselves be sensitive — pharmacy/medical, personal purchases).
- **Cardholder name** and often the **last 4 digits of the payment card** (standard on card terminal receipts).
- **Home/delivery address, email, phone** (common on online-order invoices).
- The bigger concern the user named: **full bank details** — a supplier *invoice* frequently prints the payee's sort code + account number for BACS payment. The whole image is sent, so these reach Google even though the extractor's schema (`extractor.rb:24-33`) never asks for them.

**Google's data-use terms — what determines the risk:**
The retention/training policy hinges on **which tier the API key belongs to**, which I cannot determine from the code — you must check it in the Google console. The determinant is **whether billing is enabled on the Google Cloud / AI Studio project behind the key** (and whether it's the Gemini Developer API vs Vertex AI):

- **Free tier (unpaid "Gemini API", typically an AI Studio key with no billing):** Google's Gemini API Additional Terms state Google **uses your prompts and responses to improve its products**, and **human reviewers may read them**. Their guidance explicitly says *do not submit sensitive, confidential, or personal data* on the free tier. Retention is longer and tied to that review.
- **Paid tier (billing enabled) / Vertex AI:** Google states it does **not** use your prompts or responses to train models; data is retained only briefly (abuse/safety monitoring) with no human review-for-improvement.

**Flag:** the setup guide points at the worst case. `docs/superpowers/specs/2026-07-09-reimbursements-setup-guide.md:71-74` says to *"Reuse the bedlam-bacs `GEMINI_API_KEY`, or mint a fresh one in **Google AI Studio**"* — an AI Studio key with no billing attached is a **free-tier** key, i.e. the tier under which Google may train on and human-review the receipts. I am **not asserting** that's the actual plan (the key value lives in credentials/ENV and the bedlam-bacs project's billing status isn't visible here) — but this must be verified before anything else, because on the free tier the app is currently sending student home addresses and supplier bank details to a corpus Google may retain, train on, and have humans read. That verification is the single highest-value action regardless of the opt-in work.

### 3. "Better way to extract" — options for this app

Constraints that matter here: small student-theatre app, tiny volume, prefill **must never block** submission (`ExpenseForm` docs + `extractor.rb:6-8`), and it's a genuine convenience (receipt-first UX is the whole design, spec design doc line 20).

**(i) Opt-in manual trigger ("Scan receipt" button).** *Pros:* smallest change; removes the surprise of auto-transmission; user consents per-receipt; keeps the useful feature for those who want it; trivially satisfies "never block" (no scan = plain manual form, which already works). *Cons:* doesn't reduce what's sent *when* they do click; doesn't address the free-tier-training question. **This is the user's proposal (b) and is clearly worth doing.**

**(ii) Redaction/pre-processing before send.** Blur/strip card numbers, bank details, addresses before upload. *Cons:* to know what to redact you'd need to OCR/detect it first — a chicken-and-egg problem; reliably finding sort codes/PANs on arbitrary receipt layouts is itself an ML task and would leak if imperfect. High effort, fragile, false confidence. **Not proportionate for this app.**

**(iii) Self-hosted local OCR (e.g. Tesseract).** *Pros:* nothing leaves the server; fully private. *Cons:* Tesseract gives you raw text, not the structured fields (merchant/total/VAT/budget-match) the current schema returns — you'd have to build the parsing/heuristics the LLM currently does for free, and student receipts are messy (photos, angles, thermal fade) where Tesseract accuracy is poor. It's a real infra + maintenance burden (native binary, language data, image preprocessing) for a low-volume app. Would meaningfully degrade the prefill quality. **Highest privacy, but poor cost/benefit here unless privacy is treated as non-negotiable.**

**(iv) Don't scan at all.** *Pros:* zero privacy exposure; the manual form already fully works (it's the JS-off fallback today). *Cons:* loses the receipt-first convenience that's central to the design. **Viable as the default if combined with (i): manual by default, scan on explicit opt-in.**

**Recommendation:** Do **(i) opt-in button** now (low effort, directly addresses the concern, keeps the feature). In parallel, **verify the API-key tier** and, if it's free-tier, either move the key to a **paid/billing-enabled project** (which flips Google's training/retention terms) or treat that as a blocker. Optionally add a short consent line next to the Scan button ("This sends your receipt to Google Gemini to read it"). I'd **not** pursue (ii) redaction (fragile) and would only reach for (iii) Tesseract if the org decides no receipt may ever leave the server — in which case accept the quality drop.

### 4. Concrete opt-in button design

**Where the trigger currently fires:** `_form.html.erb:72` — `change->reimbursements-receipt#extract`. Remove `extract` from that `change` action so selecting a file no longer auto-sends. Keep `change->...#stash` (that only holds the file in JS for the 422 re-render; no network).

**Change set (no new controller action needed — the `extract` endpoint and JS method already exist and are reused as-is):**

1. **`app/views/admin/reimbursements/expenses/_form.html.erb`**
   - Line 72: change the file input action from
     `action: "change->reimbursements-receipt#extract change->reimbursements-receipt#stash"`
     to just `action: "change->reimbursements-receipt#stash"`.
   - Add a **"Scan receipt"** button inside the receipt box (near line 74), wired to the existing method and disabled until a file is present:
     ```erb
     <button type="button" class="<%= btn_classes(:secondary, :sm) %>"
             data-reimbursements-receipt-target="scanButton"
             data-action="reimbursements-receipt#extract" disabled>
       Scan receipt to prefill the form
     </button>
     <p class="mt-1 text-sm text-gray-600">
       Optional. This sends your receipt to Google Gemini to read it and fill in
       the fields below. You can skip this and type the details in yourself.
     </p>
     ```
   - Update the existing helper copy at lines 62-67 so it no longer says "we'll read it" automatically ("Upload your receipt, then press **Scan** if you'd like us to prefill the form").

2. **`app/javascript/controllers/reimbursements_receipt_controller.js`**
   - Add `"scanButton"` to `static targets` (line 21-23).
   - In `stash()` (or a new `filesChanged()` bound to the `change` action), enable/disable the scan button based on `this.filesTarget.files.length`, so the button is only clickable once a file is chosen. Reset its enabled state on `#restoreOrClearStash`.
   - `extract()` (lines 80-104) needs **no change** — it already reads `this.filesTarget.files`, POSTs, and calls `#fill`. It's simply now invoked by a click instead of the `change` event. The "never block" property is preserved automatically: the manual form is fully usable whether or not the button is ever clicked, and `extract()` already swallows failures into a status message (lines 101-103).
   - Optional nicety: after a successful scan, set the button text to "Re-scan" so adding a second receipt and re-scanning still works (re-extraction already protects hand-edited fields via `editedFieldNames`, lines 39-47 / 160-165).

3. **Server side:** no change required. `ExpensesController#extract` (`expenses_controller.rb:93-106`), the route (`config/routes.rb:76`), the `extractor` seam (`base_controller.rb:46-48`), and `ExpenseForm` validation are all untouched — the endpoint just gets hit on demand rather than on upload.

4. **Tests to update (do not implement, but flag):** `test/system/admin/reimbursements/producer_js_test.rb` almost certainly drives the auto-extract-on-upload flow and will need to click the new button instead. `test/functional/admin/reimbursements/expenses_controller_test.rb` exercises the `extract` action directly and should be unaffected (it's still a POST to the same endpoint).

**Email-in path (`MailboxPollJob`) is separate** and out of scope for a "button" — there's no user present to click. If the privacy concern extends to email-in, that path can only be made opt-in by *not* extracting inbound receipts (create a blank draft + "please complete in the portal", which the spec already lists as the failure fallback, design doc line 108). Worth raising with the user as a follow-up decision; I would not bundle it into the button change.

---

**Bottom line:** Today the full receipt image (with any card/bank/address data on it) plus the budget list is sent to Gemini automatically the moment a file is picked, and again automatically for every email-in attachment. The opt-in button is a small, safe, well-scoped change (two files, reusing the existing endpoint) and directly fixes the "it happens without me asking" concern. But the button doesn't change *what* Google may do with the data once sent — so verifying the API key is on a paid/billing-enabled tier (not a free AI Studio key, which the setup guide implies) is the more important privacy action and should happen alongside it.

---

## Root-cause receipt upload bad URI

Reproduced exactly, and the fix verified. Here is the complete root-cause analysis and patch.

### Root cause

`Reimbursements::GraphClient#upload_to_folder` builds the Graph "path-addressing" upload URL by interpolating the raw filename into the path, sanitising **only** slashes/backslashes:

`/home/mick/Stack/Programmeren/BlackLightning/app/services/reimbursements/graph_client.rb:112-117`
```ruby
safe_name = filename.to_s.tr("/\\", "__")            # line 112 — replaces / and \ only
...
url = "#{GraphAuth::GRAPH_URL}/drives/#{drive_id}/items/#{folder_id}:/#{safe_name}:/content"       # 114 (simple upload)
session_url = "...items/#{folder_id}:/#{safe_name}:/createUploadSession"                            # 117 (>4 MB upload)
```

`safe_name` still contains raw spaces, parentheses, and the `(2)`. That string is then passed to Ruby's `Kernel#URI`:
- Simple upload (<4 MB): `URI(url)` in `graph_raw_request` at `/home/mick/Stack/Programmeren/BlackLightning/app/services/reimbursements/graph_auth.rb:47`.
- Large upload (≥4 MB): `URI("#{GRAPH_URL}#{path}")` in `graph_uri` at `graph_auth.rb:59`.

`Kernel#URI` uses `URI::RFC2396_Parser`, which rejects unencoded spaces and raises `URI::InvalidURIError: bad URI (is not URI?): "..."` — the exact production message. (Reproduced above with the real filename.)

The `:` delimiters in Graph's `items/{id}:/{path}:/content` addressing must stay literal, but the filename *segment* between them must be percent-encoded. Nothing encodes it today, so any receipt whose name has a space or paren (i.e. most of them) fails before the PUT is ever sent.

### Exact patch

Encode only the sanitised filename segment; the literal `:/ … :/content` delimiters are outside the interpolation and stay intact. Use `ERB::Util.url_encode` (Ruby stdlib, already loaded under Rails) — it percent-encodes everything except RFC 3986 unreserved chars, emitting `%20` for spaces (not `+`). **Do not** use `CGI.escape`, which encodes spaces as `+` and would corrupt the path. (Addressable 2.9.0 is present but only as a transitive dep via capybara, not a direct Gemfile entry, so stdlib is the cleaner choice.)

File: `/home/mick/Stack/Programmeren/BlackLightning/app/services/reimbursements/graph_client.rb`, line 112.

Before:
```ruby
      safe_name = filename.to_s.tr("/\\", "__")
```

After:
```ruby
      # Sanitise path separators, then percent-encode the filename segment so
      # spaces/parens/&c. don't blow up URI() ("bad URI (is not URI?)"). Only the
      # segment is encoded — Graph's ":/…:/content" addressing delimiters, which
      # live in the literal format string below, must stay unencoded.
      safe_name = ERB::Util.url_encode(filename.to_s.tr("/\\", "__"))
```

This one change fixes both the simple (line 114) and chunked (line 117) upload paths, since both interpolate `safe_name`. Existing behaviour is preserved: a clean name like `a_b.pdf` round-trips unchanged (verified above), so the current assertion at `graph_client_test.rb:125` still holds.

### Regression test location

Add to `/home/mick/Stack/Programmeren/BlackLightning/test/services/reimbursements/graph_client_test.rb`, immediately after the existing "does a simple PUT" test (after line 127). It should upload a filename containing spaces and parentheses and assert the recorded request URI is the percent-encoded form (and that `URI()` did not raise). The suite's `FakeHttp` records `request.uri`, and `graph_raw_request` calls `URI(url)` before handing it to the transport, so a failure to encode reproduces the production exception directly. Suggested test:

```ruby
test "upload_to_folder percent-encodes spaces and parens in the filename segment" do
  client, http = build_client([
    token_response,
    [ 201, { webUrl: "https://sp.example/receipts/r.pdf" }.to_json ]
  ])

  url = client.upload_to_folder(
    drive_id: "drv", folder_id: "fld",
    filename: "Photoshoot props (2).jpeg", content: "BYTES"
  )

  assert_equal "https://sp.example/receipts/r.pdf", url
  put = http.requests.last
  assert_includes put.uri.to_s,
    "/drives/drv/items/fld:/Photoshoot%20props%20%282%29.jpeg:/content",
    "filename segment percent-encoded, Graph ':/…:/content' delimiters preserved"
end
```

Optionally mirror it for the chunked path (filename with spaces + `content` ≥ `SIMPLE_UPLOAD_LIMIT`) to cover the `createUploadSession` URL built via `graph_uri` at `graph_auth.rb:59`.

Note (out of scope, but adjacent): `upload_to_folder` is the only place that path-addresses by filename; `get_site` (`graph_client.rb:163`) interpolates `uri.path` into `/sites/{host}:{path}` but that comes from a configured SharePoint site URL, not user filenames, so it's not part of this bug.

---

## Design budget/forecast overview

I have a complete picture of the data model and existing UI. Here is the design proposal.

---

## Budget/Forecast Overview — Design & Scoping

### 1. Current data model (what exists today)

The reimbursements domain is now **ActiveRecord-backed** (the latest commit `e1fabb41` flipped `REIMBURSEMENTS_BACKEND` default to `database`; the Airtable POROs under `Reimbursements::Airtable::*` are slated for deletion in the post-flip cleanup). All money is stored **excl-VAT**, mirroring the BACS spreadsheet.

**Core tables/models:**

| Model | File | Key fields |
|---|---|---|
| `Budget` | `app/models/reimbursements/budget.rb` | `nominal_code`, `initial_budget`, `budget_type` (`Expense`/`Income`), `active`, `cost_centre_id`, `financial_year_id` |
| `BudgetForecast` | `app/models/reimbursements/budget_forecast.rb` | `amount`, `date`, `reason`, `budget_id` — a versioned log; latest by `date desc` = current forecast |
| `Expense` | `app/models/reimbursements/expense.rb` | `amount`, `amount_excl_vat`, `status`, `nominal_code_override`, `budget_id` |
| `EusaActual` | `app/models/reimbursements/eusa_actual.rb` | `nominal_code`, `debit`, `credit`, `net`, `period`, `budget_id`, `expense_id` |
| `CostCentre` | `app/models/reimbursements/cost_centre.rb` | `eusa_code` (F40), `key`, `name` |
| `FinancialYear` | `app/models/reimbursements/financial_year.rb` | `label`, `active` (exactly one active) |

**Status lifecycle** (`app/models/reimbursements/status.rb`): `Draft → Pending → Approved → Submitted → Paid` (plus `Rejected`).

**Existing rollups on `Budget`** (already computed in Ruby, memoized, from preloaded associations):
- `committed_amount` = Σ `amount_excl_vat` where status ∈ `{Approved, Submitted, Paid}`
- `total_paid` = Σ `amount_excl_vat` where status = `Paid`
- `current_forecast` = latest `BudgetForecast.amount` (nil if none)
- `remaining` = `current_forecast − committed_amount`
- `variance` = `current_forecast − initial_budget`
- `over_budget?` / `over_initial_budget?` health flags in `app/models/reimbursements/budget_health.rb`

**How "actuals" connect:** `EusaActual` rows are imported by the Reconcile wizard (`app/services/reimbursements/reconciliation.rb`). Debit rows match to an **expense** by nominal code + amount + nearest date (`match_debit_to_expense`) → `eusa_actual.expense_id`. Credit rows (income) match to a **budget** by nominal code (`match_credit_to_budget`) → `eusa_actual.budget_id`. So **for an Expense budget the reconciled actual lives one hop away** (actual → expense → budget), while **for an Income budget it's directly on `eusa_actual.budget_id`**. `effective_nominal_code` on an expense = `nominal_code_override || budget.nominal_code` (`app/models/reimbursements/effective_payee.rb:35`).

**Existing UI:**
- Budgets index (`app/views/admin/reimbursements/budgets/index.html.erb`) — one row per budget: Initial, Current forecast, Committed, Total paid, Remaining, Variance. **Not grouped by nominal code.**
- Budget edit (`.../budgets/edit.html.erb`) — read-only financials card + a per-budget forecast log with add/edit/delete of **individual, standalone** forecasts.
- Actuals index (`.../actuals/index.html.erb`) — raw EUSA ledger browser, filterable by period.
- `BudgetsController` at `app/controllers/admin/reimbursements/budgets_controller.rb`; finance surfaces gated by `:manage, :reimbursements_finance` via `FinanceController`.

### 2. Concrete meanings for projected / committed / actual

Proposed definitions in terms of existing data (all excl-VAT, scoped to the active `FinancialYear`):

- **Projected** = `current_forecast` if a forecast exists, else `initial_budget`. The current *plan* for the line. (Rename ambiguity: today "forecast" and "projected" are the same thing — the latest `BudgetForecast`.)
- **Committed** = existing `committed_amount` (status ∈ {Approved, Submitted, Paid}). Money promised/in-flight. **Open question:** should `Pending` (submitted but not yet finance-approved) count as committed, or get its own "pipeline" column? Today it's excluded.
- **Actual** — two candidate sources that can legitimately differ:
  - **(a) Simple / already-computed:** `total_paid` (status = `Paid`). Zero new query.
  - **(b) Ledger-true:** Σ of reconciled `EusaActual` debits for this budget's expenses (+ direct credit actuals for income budgets). Authoritative EUSA ledger, but needs a new join (actual → expense → budget).

  **Recommendation:** ship **(a) `total_paid` as "Actual" in v1** (it's what the portal knows and requires no new query), and add **(b) as a Phase-2 refinement** — ideally show both as "Paid (portal)" vs "EUSA actual" once reconciliation coverage is trusted, since a divergence between them is itself a useful reconciliation signal.

**Assumptions to confirm:** amounts excl-VAT throughout; a single active financial year (the year-selector is still unbuilt per the roadmap); Income budgets invert (actual = credits, and `over_budget?` already treats income specially).

### 3. Item 1 — nominal-code budget overview

A new **Overview** page grouping budgets by `nominal_code`, with subtotals and a grand total, columns: **Initial · Projected · Committed · Actual · Expected (§4) · Remaining · Variance**. It should also surface **unbudgeted actuals** — `EusaActual` rows whose nominal code matches no active budget (real spend against a code with no plan).

**Model additions** (`app/models/reimbursements/budget.rb`):
```ruby
def projected_amount = current_forecast || initial_budget
def actual_amount    = total_paid            # v1; Phase-2 swaps in ledger-true sum
def expected_amount                          # see §4
  [ projected_amount, actual_amount, committed_amount ].compact.max
end
```

**Query sketch** — because aggregation reads across expenses/actuals, put the grouping in `DatabaseStore` (not the shared `StoreQueries`, which both backends must satisfy — the Airtable store is being deleted, so new aggregation should be database-only; **flag as open question** whether to keep `StoreQueries` parity):
```ruby
# DatabaseStore
def budgets_by_nominal_code
  budgets.group_by { |b| b.nominal_code.presence || "(none)" }
         .sort.to_h                      # {code => [Budget, ...]}
end

def unbudgeted_actuals
  codes = budgets.map(&:nominal_code).to_set
  eusa_actuals.reject { |a| codes.include?(a.nominal_code) }
end
```
Subtotals are just `.sum` over each metric per group in the view/controller (a small presenter object — e.g. `NominalCodeRollup = Struct.new(:code, :budgets)` with `#projected`, `#committed`, `#actual`, … summing its budgets — keeps the ERB clean). Reuse `reimbursements_money` from `app/helpers/reimbursements_helper.rb`.

**Route** (`config/routes.rb`, inside the budgets block):
```ruby
resources :budgets, only: %i[index edit update] do
  collection { get :overview }        # /admin/reimbursements/budgets/overview
end
```
New action `BudgetsController#overview` + `app/views/admin/reimbursements/budgets/overview.html.erb` (grouped table with `<tbody>` per nominal code, a subtotal row, a grand-total footer, and an "Unbudgeted spend" section). Link it from the budgets index and the Finance sidebar.

### 4. Item 3 — the max(forecast, actual) column, not called "forecast"

Add **`expected_amount = [projected, actual, committed].compact.max`** (I fold in `committed` too — committed can exceed a stale forecast just as actual can; the point of the column is "the most it could realistically end up costing"). **State the semantics** in the column tooltip: *"the greater of the current projection and what's already been spent/committed — so the number never drops below reality as spend lands."*

**Naming** (must avoid "forecast"): recommend **"Expected"** for the column header, or **"Expected outturn"** if you want the UK-finance term of art (*outturn* = the actual final result of a budget line — exactly this concept). Other options: "Anticipated", "Best estimate", "Projected outturn". My pick: **"Expected outturn"** (accurate to finance readers) with a plain-English tooltip.

This column belongs on both the per-budget index and the new nominal-code overview, and drives a cleaner `over_budget?` story: `remaining` could be recomputed as `projected − expected` for the badge, so a line silently overspending past a stale forecast turns red without anyone re-logging a forecast. (Leave the existing `remaining`/`over_budget?` as-is for v1 to avoid changing the badge semantics mid-cutover; note it as a follow-up.)

### 5. Item 2 — annotatable "budget update" batches

Today each `BudgetForecast` is standalone per budget. The request: revise several budgets' forecasts **in one action** and annotate the whole revision once (e.g. after a production budget meeting).

**New table + model** — a parent that groups forecast rows:
```ruby
# db/migrate/…_create_reimbursements_budget_updates.rb
create_table :reimbursements_budget_updates do |t|
  t.references :financial_year, foreign_key: { to_table: :reimbursements_financial_years }
  t.date   :effective_date, null: false
  t.text   :note                         # the shared annotation
  t.references :created_by, foreign_key: { to_table: :users }   # who logged it
  t.timestamps
end
# and add the join column to the existing forecasts table:
add_reference :reimbursements_budget_forecasts, :budget_update,
              foreign_key: { to_table: :reimbursements_budget_updates }   # nullable
```
`app/models/reimbursements/budget_update.rb`: `has_many :forecasts`, `belongs_to :financial_year`, `belongs_to :created_by, class_name: "User"`. The nullable `budget_update_id` on `BudgetForecast` is **backward-compatible** — all existing standalone forecasts stay `nil`, and the "latest forecast wins" logic in `Budget#current_forecast` is untouched (a batched forecast is still just a `BudgetForecast` row).

**UI:** a "New budget update" flow (`BudgetUpdatesController#new/create`) that lists active budgets with a "new forecast amount" input each, plus one shared `effective_date` + `note`; on submit it creates the `BudgetUpdate` and one `BudgetForecast` per changed budget linked to it. The per-budget forecast log (edit page) then shows the shared note; an index of budget updates lets you review/annotate a whole revision.

**Note:** this is genuinely unbuilt — no grouping table exists. It's the largest of the three.

### Phasing, files, and open questions

**Phase 1 — quick win (model methods + two columns).** Add `projected_amount`, `actual_amount`, `expected_amount` to `Budget`; add **Actual** and **Expected outturn** columns to the existing budgets index and edit financials card.
- Touch: `app/models/reimbursements/budget.rb`, `app/views/admin/reimbursements/budgets/index.html.erb`, `.../budgets/edit.html.erb`, tests under `test/models/reimbursements/` and `test/controllers/admin/reimbursements/`. No migration.

**Phase 2 — nominal-code overview (new page).** Grouped/subtotalled table + unbudgeted-actuals section + ledger-true actual refinement.
- Touch: `config/routes.rb`, `app/controllers/admin/reimbursements/budgets_controller.rb`, new `app/views/admin/reimbursements/budgets/overview.html.erb`, `app/services/reimbursements/database_store.rb` (grouping + `unbudgeted_actuals`), a small presenter (e.g. `app/models/reimbursements/nominal_code_rollup.rb`), sidebar link in the Finance nav, tests. Optional: `Budget#actual_amount` → EUSA-ledger sum.

**Phase 3 — annotatable budget updates (new model).** Migration + model + multi-budget form + updates index.
- Touch: new migration under `db/migrate/`, `app/models/reimbursements/budget_update.rb`, `add_reference` to forecasts, `config/routes.rb`, new `BudgetUpdatesController` + views, `DatabaseStore` writer methods (mirroring `create_forecast!`), `db/schema.rb`, model annotations, tests. This changes schema → per your workflow, **pause for review before merging** (schema/migration + new interface).

**Already partially built / reusable:** versioned forecasts (`BudgetForecast`), committed/paid/forecast/remaining/variance rollups, over-budget health flags, per-nominal-code data on budgets/expenses/actuals, the `reimbursements_money`/`reimbursements_date` helpers, EUSA actuals import + linkage, and `FinancialYear`/`CostCentre` scoping scaffolding (schema shipped, UI mostly pending per `docs/reimbursements/mysql-migration-and-roadmap.md`). The roadmap mentions multi-year and per-cost-centre scoping but **does not** mention this budget-overview work — it's net-new backlog.

**Open questions for the user to decide:**
1. Does **Actual** mean portal `total_paid` or the EUSA-reconciled ledger sum (or show both)?
2. Should **Pending** expenses count toward Committed, or get a separate "pipeline" column?
3. Column name: **"Expected outturn"** vs "Expected" vs "Anticipated" — and should `max()` include committed, or strictly `max(forecast, actual)` as literally requested?
4. Overview grouping: **budgets grouped under a shared nominal code**, or one row per nominal code with budgets collapsed? (Multiple budgets can share a code.)
5. Do the new aggregations need to work on the Airtable store too, or is it fine to build **database-only** (given Airtable is being deleted)? Recommend database-only.
6. Should the over-budget badge switch to `projected − expected` once "Expected" exists (v1 keeps it as-is)?
7. Budget updates: should editing a batched forecast be allowed, and should the batch capture `created_by` (needs a `users` FK)?

---

## Design CSV/xlsx exports

I have a complete picture. Here is the design proposal.

---

## Reimbursements Exports — Design Proposal

### 1. What already exists (reuse this, don't reinvent)

**CSV is already a solved pattern in this portal — two views have it:**

- `ExpenseEditsController#index` ("Expenses") — `app/controllers/admin/reimbursements/expense_edits_controller.rb:43-46` + private `expenses_csv` (`:149-171`).
- `ActualsController#index` ("EUSA Actuals") — `app/controllers/admin/reimbursements/actuals_controller.rb:25-28` + private `actuals_csv` (`:41-59`).

Both follow the identical shape, and it already honours "URL as state":

```ruby
respond_to do |format|
  format.html { @expenses = paginate(filtered) }        # pagination is display-only
  format.csv  { send_data expenses_csv(filtered), ... }  # exports the FULL filtered set
end
```

The view link (the pattern to copy verbatim), e.g. `app/views/admin/reimbursements/expense_edits/index.html.erb:44`:

```erb
<%= link_to "Download CSV",
      admin_reimbursements_expense_edits_path(request.query_parameters.merge(format: :csv)) %>
```

`request.query_parameters.merge(format: :csv)` carries the current Ransack/filter params straight into the download — this is exactly the convention the task asks for. Rails' default `.:format` route segment means no route changes are needed to add `format.csv` to any of these index actions.

**Xlsx libraries already in the Gemfile** (`Gemfile:36-38`, locked):
- `caxlsx` 4.5.0 (Axlsx) — builds workbooks from scratch. **This is the gem for the combined multi-sheet workbook.** Already used across `lib/reports/*` (see `lib/reports/staffing.rb:21` — `Axlsx::Package.new`, `wb.add_worksheet`, `sheet.add_row`).
- `rubyXL` 3.4.38 — fills the vendored BACS template in place preserving EUSA styling (`app/services/reimbursements/bacs_xlsx.rb`). Not for building new sheets.
- `roo` 3.0.0 — reading only.

**Axlsx serving:** `Reports::*` build an `Axlsx::Package` and serialise with `package.to_stream.read` (`app/mailers/reports_mailer.rb:15`), currently *emailed* via `deliver_later`. No `caxlsx_rails`, and no `Mime[:xlsx]` registration exists — so serve with an explicit content-type string.

**Store API** (both `DatabaseStore` and the Airtable `Store` expose the same frozen surface): `store.expenses`, `store.budgets`, `store.people`, `store.batches`, `store.eusa_actuals` all return **in-memory cached arrays**. A combined workbook can pull the whole dataset with **0 backend/API calls on a warm cache** — critical for the Airtable free-plan backend during the cutover.

### 2. Inventory of exportable views

| Controller#action | Title | Gate | Columns shown |
|---|---|---|---|
| `ExpenseEditsController#index` | Expenses | finance | #, Status, Payee, Budget, Amount, Amount ex VAT, Description, Payment reference, Submitted, Needs attention — **CSV done** |
| `ActualsController#index` | EUSA Actuals | finance | Date, Type, Description, Amount, Budget, Linked expense, Period — **CSV done** |
| `BudgetsController#index` | Budgets | finance | Budget, Type, Visible, Initial, Current forecast, Committed, Total paid, Remaining, Variance, Owners (`budgets/index.html.erb:15`) |
| `PeopleController#index` | People | finance | Name, Email, modulus status, Verified — underlying: sort_code, account_number (**sensitive bank details**) |
| `BatchesController#index` | Batch history | finance | Batch date_sent, expenses grouped per batch (`batches_controller.rb:24-26`) |
| `ReviewController#index` | Review Expenses | finance | Pending/Approved tabs — same expense shape as ExpenseEdits (can reuse the Expenses exporter) |
| `MyBudgetsController#index` | My Budgets | **base access** (`:access, :reimbursements`), owner-facing | Owned budgets + their pending expenses |

`FinanceController#index` is a dashboard, not a list — a good home for the "Download combined workbook" button.

### 3. Proposed CSV approach — one exporter object per resource, feeding both formats

The current inline `*_csv` private methods don't scale to 5-7 views and duplicate the `CSV.generate` boilerplate. Extract a small PORO family under **`app/services/reimbursements/exports/`** where each class owns its column definition **once**, and that single definition drives *both* the per-view CSV and the combined-workbook sheet (fully DRY across both backlog items):

```ruby
# app/services/reimbursements/exports/base.rb
module Reimbursements
  module Exports
    class Base
      def initialize(store:, helpers:, checker: nil)
        @store, @helpers, @checker = store, helpers, checker
      end

      def headers = self.class::HEADERS
      def rows(collection) = collection.map { |record| row(record) } # subclass defines #row

      def to_csv(collection)
        CSV.generate do |csv|
          csv << headers
          rows(collection).each { |r| csv << r.map { |v| sanitize(v) } }
        end
      end

      def add_sheet(workbook, collection, name:)
        workbook.add_worksheet(name: name) do |sheet|
          sheet.add_row(headers)
          rows(collection).each { |r| sheet.add_row(r.map { |v| sanitize(v) }) }
        end
      end

      private
      # Reuse BacsXlsx's formula-injection guard (=, +, -, @, tab/CR/LF) —
      # see finding below; the existing CSV exports omit this today.
      def sanitize(value) = ::Reimbursements::BacsXlsx.sanitize_value(value)
    end
  end
end
```

Concrete subclasses: `Exports::Expenses`, `Exports::Actuals`, `Exports::Budgets`, `Exports::People`, `Exports::Batches` — each defines `HEADERS` and `#row(record)`, moving the logic already in `expenses_csv`/`actuals_csv` into `Exports::Expenses`/`Exports::Actuals`.

**Controller change** (repeated per view, ~4 lines):
```ruby
format.csv do
  send_data Exports::Budgets.new(store: store, helpers: helpers).to_csv(sorted),
            type: "text/csv",
            filename: "reimbursements-budgets-#{Date.current.iso8601}.csv"
end
```
plus the "Download CSV" `link_to … merge(format: :csv)` in each index view. Refactor the two existing controllers onto the exporters too (they gain the formula-sanitisation for free).

### 4. Proposed combined xlsx — one workbook, sheet-per-resource

- **Gem:** `caxlsx`/Axlsx (already loaded, already the house style in `lib/reports/`).
- **New route** under the existing namespace (`config/routes.rb`, after `resources :actuals`):
  ```ruby
  resource :export, only: :show, controller: "exports"   # GET /admin/reimbursements/export.xlsx
  ```
- **New controller** `app/controllers/admin/reimbursements/exports_controller.rb < FinanceController` (finance-gated):
  ```ruby
  def show
    package = Axlsx::Package.new
    wb = package.workbook
    Exports::Expenses.new(store:, helpers:).add_sheet(wb, store.expenses,      name: "Expenses")
    Exports::Actuals.new(store:, helpers:).add_sheet(wb, store.eusa_actuals,   name: "Actuals")
    Exports::Budgets.new(store:, helpers:).add_sheet(wb, store.budgets,        name: "Budgets")
    Exports::Batches.new(store:, helpers:).add_sheet(wb, store.batches,        name: "Batches")
    send_data package.to_stream.read,
              filename: "reimbursements-#{Date.current.iso8601}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
  ```
- **Link** a "Download workbook (xlsx)" button from `FinanceController#index` dashboard and/or the Expenses index toolbar.
- Serve **inline** (not emailed like `Reports::*`): the datasets are small in-memory arrays, so `to_stream.read` in-request is fine and simpler. If a future dataset grows large, the `Reports::Staffing` + `ReportsMailer.deliver_later` pattern is the ready escape hatch.

### 5. Phased plan

- **Phase 1 — CSV for every view.** Create `Exports::Base` + the 5 resource exporters; migrate `ExpenseEditsController`/`ActualsController` onto them; add `format.csv` + a "Download CSV" link to Budgets, People, Batches, (and Review — reuse `Exports::Expenses`). Test at request level (`get …, format: :csv`, assert headers + a known row); no browser needed.
- **Phase 2 — combined workbook.** Add `add_sheet` (already on Base), the `ExportsController`, the route, and the dashboard button. Test: `get export.xlsx`, parse with the already-present `roo` to assert sheet names + first data row.

### Findings / open questions

1. **Formula-injection gap in the existing CSV exports.** `expenses_csv`/`actuals_csv` write submitter-controlled text (description, payee) into cells with no sanitisation, while `BacsXlsx#sanitize` (`bacs_xlsx.rb:112-117`) guards exactly this for the same data going to xlsx. A cell starting with `= + - @` executes on CSV re-import into Excel/Sheets. The shared `Exports::Base` should route all values through that guard — worth extracting `BacsXlsx.sanitize_value` as a shared class method (or a small `Reimbursements::CellSanitizer`). Flag this as a real (low-sev) security fix folded into the refactor.
2. **People export contains bank details** (sort code, account number). It's finance-gated and the BACS xlsx already carries them, so it's consistent — but confirm whether the combined workbook should include full account numbers or mask them.
3. **Sheet-name length:** Excel caps worksheet names at 31 chars — the fixed names above are fine; just don't template dates into them.
4. **Batches export shape:** the batch list groups expenses per batch (`@expenses_by_batch`). Decide whether the Batches sheet is one-row-per-batch (summary) or one-row-per-expense-with-batch-columns. One-row-per-batch matches the on-screen list.
5. **Backend switch is transparent** — everything goes through `store.*`, so both Airtable and DatabaseStore backends export identically with no per-backend code.

---

## Investigate EUSA actuals import

I now have a complete picture. Here are my findings and design proposal.

---

## EUSA Actuals — current state + design proposal

### 1. Current state: how EUSA actuals are imported and stored

#### Import is paste-driven, not file-upload
There is **no file parser**. Actuals enter through a stateless three-step paste wizard, `Admin::Reimbursements::ReconcileController` (`app/controllers/admin/reimbursements/reconcile_controller.rb`), routed at `resource :reconciliation` (`show` → `preview` → `apply`, `config/routes.rb:124-128`). The operator copies the monthly EUSA ledger export and pastes tab- or comma-separated text into a textarea; nothing is stashed in the session — preview and apply both re-parse the pasted text (the parse/match functions are pure).

#### Parsing — `Reimbursements::Reconciliation` (`app/services/reimbursements/reconciliation.rb`)
- `parse_actuals_rows(text, cost_centre_code: "F40")` returns `ActualsRow` Data objects. It auto-detects the delimiter (tab if the first line has one, else comma) and is **header-driven** via `build_col_map`/`column_key_for`, so column order and extra columns don't matter.
- **Two layouts supported:**
  - **Legacy 10-column:** `Nominal, Cost Centre, Ref, Date, Period, Narrative, Narrative 1, Debit, Credit, Net`.
  - **Sage export:** a single signed `GoodsValue` column, split into `debit` (positive), `credit` (negated negative), and `net`.
- **Fields per row:** `nominal_code`, `cost_centre`, `ref`, `date` (British `DD/MM/YYYY`, ISO fallback), `period` (EUSA period P1–P12), `narrative`, `narrative_1`, `debit`, `credit`, `net` (all amounts `BigDecimal`).
- **Cost-centre filter:** rows for a different cost centre are dropped; blank cost centre is kept. The code comes from `CostCentre.default.eusa_code` (falls back `"F40"`).
- Raises `ArgumentError` on missing required columns / unparseable dates / amounts.

#### Matching (preview → apply)
- **Debit rows → expenses:** `match_debit_to_expense` — nominal code equal (case-insensitive), amount within `AMOUNT_TOLERANCE` (£0.01, ex-VAT preferred else gross), and `submitted_to_eusa_date` or `payment_confirmed_date` within `DATE_WINDOW_DAYS` (14) of the row date; closest-date candidate wins. A matched expense is marked `Paid` and its producer emailed.
- **Credit rows → income budgets:** `match_credit_to_budget` — nominal code equal only.
- Rows matching neither are saved as **unlinked** actuals.

#### Storage — `reimbursements_eusa_actuals` (`app/models/reimbursements/eusa_actual.rb`)
Columns: `nominal_code`, `cost_centre`, `credit`, `debit`, `net`, `date`, `period`, `ref`, `narrative`, `narrative_1`, `source_month`, `imported_at`, plus FKs `expense_id` (nullify), `budget_id`, `financial_year_id`, and `airtable_record_id` (legacy). Writes go through `Reimbursements::DatabaseStore` (`create_actual!`, `link_actual_to_expense!`, `link_actual_to_budget!`, `app/services/reimbursements/database_store.rb:244-268`).

#### Duplicate handling (the only "matching" that exists today)
`actuals_row_dedup_key(nominal_code, narrative, debit, credit)` — narrative-stripped, amounts normalised so `nil`/`""`/`0`/float all compare equal, exact `BigDecimal` so amounts a penny apart stay distinct. Dedup is **scoped per EUSA period** (`ReconcileController#dedup` checks each row against `store.actuals_for_period(row.period)`), so a paste spanning several periods dedups each period independently. This catches an **identical** re-paste; it does nothing for near-duplicates or offsetting pairs.

#### Read-only browser
`Admin::Reimbursements::ActualsController#index` (`resources :actuals, only: [:index]`) lists imported actuals with period filter + CSV export, badging each row Expense / Budget / Unlinked (`app/views/admin/reimbursements/actuals/index.html.erb`).

**Key gap:** nothing detects offsetting/reversing pairs. A +£50 debit under nominal A and a £50 credit under nominal B (a nominal-code reclassification that nets to zero) both import as two separate **unlinked** rows and clutter the ledger. Neither backlog item is mentioned in `docs/reimbursements/mysql-migration-and-roadmap.md` — both are net-new.

---

### 2. Backlog item 1 — auto-match offsetting transactions

#### The shape of an offset in this data
"Moving between nominal codes" appears as **two rows with the same magnitude and opposite direction**: a debit of £X under one nominal code and a credit of £X under another (often same `narrative`/`ref`, same or adjacent `date`, same `period`). They net to zero and are pure bookkeeping noise — they should be recognised as a pair and collapsed out of the "unmatched" set, **not deleted** (finance needs the audit trail).

#### Proposed heuristic (pure function in `Reconciliation`)
Add `Reconciliation.detect_offsetting_pairs(rows)` returning `[pairs, remaining]`, where each pair is a `[debit_row, credit_row]` whose amounts offset. Algorithm:

1. **Represent each row as a signed magnitude:** `signed = debit - credit` (or use `net`). Skip rows where `signed.zero?`.
2. **Bucket by absolute magnitude** rounded to the penny (`abs(signed)` as the key) — offsets share magnitude. A `Hash` keyed on the `BigDecimal` abs value (reuse the exact-`BigDecimal` discipline from `norm_amount`, never float).
3. **Within each magnitude bucket, greedily pair** one positive-signed row with one negative-signed row when they also satisfy the tuneable predicates (config constants, mirroring `AMOUNT_TOLERANCE`/`DATE_WINDOW_DAYS`):
   - **opposite sign** (required),
   - **amount within `OFFSET_AMOUNT_TOLERANCE`** (start £0.00 — exact — since these are internal transfers, loosen only if real data shows rounding),
   - **date proximity** within `OFFSET_DATE_WINDOW_DAYS` (start small, e.g. 3–7 days; internal reclass usually same-day/same-batch),
   - **different nominal code** (a reclass moves *between* codes),
   - optional tie-breaker / confidence boost: **same `narrative` or same `ref`** — when several candidates share a magnitude, prefer the pair with matching narrative/ref and closest date, exactly as `match_debit_to_expense` breaks ties by closest date.
4. Each row is consumed by at most one pair (delete from the working set on match), so N debits and N credits of the same magnitude pair up deterministically.

Return the surviving unpaired rows so the existing debit→expense / credit→budget matching runs only on genuine rows.

#### How it hooks into the import
- **`ReconcileController#build_matches`:** before the debit/credit matching loop, run `detect_offsetting_pairs` on `rows`; feed only the `remaining` rows into the current matcher. Surface `@offsetting_pairs` to the preview.
- **`preview.html.erb`:** add an "Offsetting pairs (auto-matched)" card (same table idiom as the existing Matched/Unmatched cards) so the operator *sees and can sanity-check* every collapsed pair before applying — this must be visible, never silent.
- **`#apply` / `apply_reconciliation`:** still **create both actual rows** (audit trail preserved), but link them to each other and stamp a status so they drop out of the "Unlinked" noise. Reuse the per-row `with_row_rescue` wrapper.

#### Persistence — keep an audit link, don't delete
Add to `reimbursements_eusa_actuals` (migration):
- `offset_of_id :bigint` — self-referential FK (`belongs_to :offset_of, class_name: "EusaActual", optional: true`, plus `has_one :offset_counterpart`), pointing each row of a pair at its partner; **and/or**
- a `reconciliation_status` string column (values e.g. `"unlinked"`, `"expense"`, `"budget"`, `"offset"`) so the Actuals browser can badge and filter these out of the working set.

Store methods `link_offsetting_pair!(a_id, b_id)` in `DatabaseStore` (mirrors `link_actual_to_expense!`). The Actuals index (`actuals/index.html.erb`) gains an "Offset" badge and a filter to hide offset rows by default.

#### Real-data caveat — this heuristic MUST be tuned against a real export
The constants above (tolerance, date window, whether narrative/ref reliably match, whether reclass rows share `ref`) are **guesses** until validated. I would ask the user for:

> **One or two real monthly EUSA actuals exports** (the exact text/CSV that gets pasted into Reconcile), ideally ones the finance team knows **contain a real offsetting/reclassification pair** — with those specific rows pointed out. Anonymise producer names in `narrative` if needed, but **keep `nominal_code`, `cost_centre`, `ref`, `date`, `period`, `debit`, `credit`, `net` intact**, since those are exactly the fields the heuristic keys on. Specifically I need to see: do the two legs of a reclass share the same `ref` and/or `narrative`? Are they always same-date or can they straddle days/periods? Is the magnitude ever off by rounding/VAT? Are there ever 3+ legs (a split reclass)? That determines the tolerance/window defaults and whether `ref`-equality can be a hard requirement rather than a tie-breaker.

Without that sample, I'd ship the heuristic **conservative** (exact amount, same period, narrative/ref as a required match) and loosen only where real data proves it safe — an over-eager pairer that collapses two genuine unrelated transactions is worse than leaving them unmatched.

---

### 3. Backlog item 2 — actual → expense conversion

Turn an imported EUSA actual (typically an unlinked debit — a cost EUSA levied directly, e.g. a utility or staff cost) into a portal `Expense` of type **`TYPE_FROM_EUSA`** (`"From EUSA (utility, staff cost, etc)"`), which already exists in `Expense::TYPES` precisely for internal-bookkeeping expenses that submitters never pick (`Expense::SUBMITTER_TYPES` excludes it).

#### Model / builder
Add `ExpenseForm.from_actual(actual)` (mirror of the existing `from_expense`, `app/models/reimbursements/expense_form.rb:104`) that pre-fills:
- `expense_type: Expense::TYPE_FROM_EUSA`
- `amount` / `amount_excl_vat` ← `actual.debit` (or `net`)
- `description` ← `actual.narrative` (+ `narrative_1`)
- `payment_reference` ← `actual.ref` (respecting the 18-char `REFERENCE_LIMIT`)
- `budget_record_id` ← blank for the operator to pick, or pre-selected if the actual's nominal code maps to a single budget
- `require_receipts: false` — a From-EUSA line has no receipt.

The From-EUSA path needs the VAT / large-amount / receipt soft-blocks relaxed (they exist for producer reimbursements). Either branch those validations on `expense_type == TYPE_FROM_EUSA`, or add a dedicated lightweight create path — the form already skips receipt requirement when `require_receipts?` is false, but `vat_soft_block`/`large_amount_soft_block` run on any non-draft submit and would need a From-EUSA guard.

#### UI / flow
- **Route:** on `resources :actuals` add `member { get :new_expense; post :create_expense }` (or a small dedicated `Actuals::ExpensesController`).
- **`actuals/index.html.erb`:** on each **unlinked debit** row, add a `get_link`/button "Create expense from this" (finance-gated) next to the existing Linked badge — disabled/hidden once `actual.expense_id` is set (badge already shows "Expense").
- **`new_expense`:** render the finance expense form pre-filled from `ExpenseForm.from_actual(actual)` (reuse the existing expense form partial; budget picker from `store.active_budgets`).
- **`create_expense`:** `store.create_expense!(form.create_attrs(...))` with `expense_type = TYPE_FROM_EUSA`, then **`store.link_actual_to_expense!(actual.record_id, expense.record_id)`** so the actual and expense are cross-linked (the actual's `expense_id` FK already exists and the index will badge it "Expense"). This closes the loop with the *same* linkage the reconcile wizard uses for debit matches — no new join needed.

Because a From-EUSA expense records an already-settled cost, consider creating it directly in a settled status (`Paid`, with `payment_confirmed_date = actual.date`) rather than `Pending`, so it doesn't re-enter the reimbursement/review/batch pipeline. Confirm the intended status with the user — that's the one behavioural decision worth checking.

---

### 4. Exact files to touch

**Auto-match offsetting pairs**
- `app/services/reimbursements/reconciliation.rb` — new pure `detect_offsetting_pairs` + tolerance/window constants.
- `app/controllers/admin/reimbursements/reconcile_controller.rb` — call it in `build_matches`; persist pair links in `apply_reconciliation`.
- `app/views/admin/reimbursements/reconcile/preview.html.erb` — new "Offsetting pairs" card.
- `db/migrate/…` — add `offset_of_id` (self-FK) and/or `reconciliation_status` to `reimbursements_eusa_actuals`.
- `app/models/reimbursements/eusa_actual.rb` — `belongs_to :offset_of` / `has_one` counterpart; helper predicates.
- `app/services/reimbursements/database_store.rb` — `link_offsetting_pair!`; expose status in `actual_columns`.
- `app/services/reimbursements/store_queries.rb` — optional scope to exclude offset rows from the working set.
- `app/views/admin/reimbursements/actuals/index.html.erb` — "Offset" badge + filter.
- Tests: `test/services/reimbursements/reconciliation_test.rb`, `test/functional/admin/reimbursements/reconcile_controller_test.rb`.

**Actual → expense**
- `app/models/reimbursements/expense_form.rb` — `from_actual`; From-EUSA guards on VAT/large-amount/receipt blocks.
- `config/routes.rb` — member routes on `:actuals`.
- `app/controllers/admin/reimbursements/actuals_controller.rb` (or new `Actuals::ExpensesController`) — `new_expense` / `create_expense`.
- `app/views/admin/reimbursements/actuals/index.html.erb` — "Create expense" button on unlinked debit rows; a `new_expense` view (reuse the expense form partial).
- `app/services/reimbursements/database_store.rb` — reuse `create_expense!` + `link_actual_to_expense!` (no new store method needed).
- Tests: `test/functional/admin/reimbursements/actuals_controller_test.rb`, `test/models/reimbursements/expense_form_test.rb`.

**Note on both backends:** the store API is duplicated across `DatabaseStore` and the Airtable-era `Store` (both frozen to one public API). Production has already flipped to `database` (commit `e1fabb41`), and the Airtable POROs "die with the post-flip cleanup PR" per CLAUDE.md — so I'd implement against `DatabaseStore` only and not extend the Airtable store.

### 5. The specific real-data sample to request
- **1–2 actual monthly EUSA exports** in the exact paste format, each known to contain at least one real offsetting/reclassification pair, with those rows identified.
- Fields `nominal_code, cost_centre, ref, date, period, debit, credit, net` must be intact (narrative may be anonymised).
- The questions the sample must answer: do offset legs share `ref`/`narrative`? Same date/period always, or can they straddle? Ever off by rounding/VAT? Ever 3+ legs? — these set the tolerance, date window, and whether `ref`-match is a hard requirement or a tie-breaker.

There is currently **no real EUSA sample data in the repo** — only synthetic single-row fixtures in `test/services/reimbursements/reconciliation_test.rb` (`SAMPLE_ROW = "439999\tF40\tBACS001\t15/03/2025\t03\tAlice Producer\tSome show\t123.45\t\t123.45"`). Design was done against the schema + parser + those fixtures; the offset heuristic's thresholds should not be finalised until a real export is reviewed.

---

## Find hardcoded fringe lang + em dashes

I have everything needed. Here is the exhaustive audit.

---

## TASK A — Hardcoded "Fringe" language

Architecture note that governs every verdict: the reimbursements portal is already built to be multi-cost-centre (`Reimbursements::CostCentre` has `name` = "Bedlam Fringe 2026" and `eusa_signature_name`; termtime "BED" is a planned second row) and multi-year (`Reimbursements::FinancialYear.label`). So the "correct" generic source already exists — the (b) cases are places that hardcode "Bedlam Fringe" copy/constants instead of reading `@cost_centre.name` / `eusa_signature_name`. The email templates rendered by `Notifier#send_email` currently receive **no** `cost_centre` in their `assigns`, so generalising them requires plumbing the cost centre (or a signature string) into `assigns` — flagged per row.

### A1. Reimbursements — should GENERALISE (b)

| # | file:line | Current | Verdict / proposed change |
|---|-----------|---------|---------------------------|
| 1 | `app/jobs/reimbursements/mailbox_poll_job.rb:31` | `SIGN_OFF = "Bedlam Fringe finance (automated reply)"` | generalise → `"#{cost_centre.name} finance (automated reply)"` (constant → method taking the cost centre). |
| 2 | `app/jobs/reimbursements/mailbox_poll_job.rb:328` | `<p>If you're part of Bedlam Fringe, email from the address you registered with,` | generalise → `"If you're part of #{cost_centre.name}, email from the address…"`. |
| 3 | `app/jobs/reimbursements/mailbox_poll_job.rb:331` | `<p>Questions? Contact finance@bedlamfringe.co.uk.</p>` | generalise → derive contact from cost-centre config (e.g. `receive_mailbox`), don't hardcode the address. |
| 4 | `app/jobs/reimbursements/mailbox_poll_job.rb:354` | `or contact finance@bedlamfringe.co.uk if this doesn't look right.` | same as #3 — config-driven contact address. |
| 5 | `app/jobs/reimbursements/build_batch_job.rb:38` | `SENDER_FALLBACK = "Bedlam Fringe Finance"` | generalise → fall back to `cost_centre.eusa_signature_name.presence \|\| "#{cost_centre.name} Finance"`. |
| 6 | `app/controllers/admin/reimbursements/batches_controller.rb:196` | `current_user.try(:full_name).presence \|\| "Bedlam Fringe Finance"` | generalise → same cost-centre-derived fallback as #5 (duplicated literal). |
| 7 | `app/services/reimbursements/eusa_email_composer.rb:23` | `subject: "Bedlam Fringe BACS Request - #{bacs_date.iso8601} - #{eusa_code}"` | generalise → prefix from cost-centre name, e.g. `"#{cost_centre.name} BACS Request - …"` (composer would need the name passed in; it already gets `eusa_code`). |
| 8 | `app/services/reimbursements/batch_processor.rb:71` | `bacs_filename = "#{bacs_date.iso8601}-bedlam-fringe-BACS-request-#{@cost_centre.eusa_code}.xlsx"` | generalise → slug from `@cost_centre.name` (e.g. `@cost_centre.name.parameterize`) instead of literal `bedlam-fringe`. |
| 9 | `app/services/reimbursements/notifier.rb:55` | `subject: "[Bedlam Fringe] #{count} … submitted for payment"` | generalise → note the **other** notifier subjects (lines 68/79/110/122) use `"[Bedlam BACS]"`; this one is inconsistent. Use the same prefix or `"[#{cost_centre.name}]"`. |
| 10 | `app/views/reimbursements/emails/eusa.html.erb:4` | `Please find attached the BACS request from Bedlam Fringe for …` | generalise → use the `sender_name` local (already in scope, used at line 36) or a passed cost-centre name. |
| 11 | `app/views/reimbursements/emails/eusa.html.erb:37` | sign-off `Bedlam Fringe` | generalise → same. |
| 12 | `app/views/reimbursements/emails/rejection.html.erb:36` | `Bedlam Fringe Finance` | generalise → pass `cost_centre`/signature into `Notifier` assigns; render the signature. |
| 13 | `app/views/reimbursements/emails/producer_notification.html.erb:41` | `Bedlam Fringe Finance` | generalise → same signature plumbing. |
| 14 | `app/views/reimbursements/emails/payment_confirmation.html.erb:17` | `…thanks for everything you do for Bedlam Fringe.` | generalise → `"…for #{cost_centre.name}."`. |
| 15 | `app/views/reimbursements/emails/payment_confirmation.html.erb:19` | `The Bedlam Fringe finance team` | generalise → `"The #{cost_centre.name} finance team"`. |
| 16 | `app/views/reimbursements/emails/failure.html.erb:9` | `Best,<br>Bedlam Fringe BACS (automated)` | generalise → shared automated sign-off from config (this exact line is duplicated in #17/#18/#19/#20). |
| 17 | `app/views/reimbursements/emails/pending_reminder.html.erb:32` | `Best,<br>Bedlam Fringe BACS (automated)` | generalise (duplicate of #16). |
| 18 | `app/views/reimbursements/emails/manual_review.html.erb:41` | `Best,<br>Bedlam Fringe BACS (automated)` | generalise (duplicate). |
| 19 | `app/views/reimbursements/emails/batch_ready.html.erb:56` | `Best,<br>Bedlam Fringe BACS (automated)` | generalise (duplicate). |
| 20 | `app/views/reimbursements/emails/approved_ready.html.erb:39` | `Best,<br>Bedlam Fringe BACS (automated)` | generalise (duplicate). |
| 21 | `app/views/admin/reimbursements/expenses/edit.html.erb:6` | `contact <%= mail_to "finance@bedlamfringe.co.uk" %> for changes.` | generalise → config-driven contact address (same as #3). |
| 22 | `app/services/reimbursements/airtable_importer.rb:26` | `DEFAULT_YEAR_LABEL = "Fringe 2026"` | low priority — Airtable-era importer slated to die in the post-flip cleanup; the label is already overridable via `YEAR_LABEL` env in the runbook. Generalise only if kept. |

Note the "code review" file already flags a related item: `plans/code-review-reimbursements-operator-tooling.md:732` (`bacs_xlsx.rb#write_row` hardcodes `"F40"` as a cost-centre fallback) — same class of Fringe-specific hardcoding, worth folding into this pass.

### A2. Reimbursements — KEEP (comments / config data / legit)

- `app/services/reimbursements/amount_validation.rb:23` — code comment ("no real Bedlam Fringe expense claim…"). Keep (could reword to generic, cosmetic only).
- `app/models/reimbursements/cost_centre.rb:31,67`, `financial_year.rb:21`, `db/migrate/20260717100000_create_reimbursements_financial_years.rb:2`, `mailbox_poll_job.rb:46` — comments. Keep.
- `db/seeds/reimbursements.rb:1,5,7,9,10` — this **is** the cost-centre config (name/mailboxes for the Fringe row). Keep — correct place for it.
- `app/services/reimbursements/prompt_safety.rb` (not a Fringe hit, noted for Task B).

### A3. Rest of app — KEEP (legitimately about the Fringe festival)

- `config/routes.rb:471` — redirect to a real external Theatre Paradok Fringe-show URL. Keep.
- `db/seeds/event_tags.rb:12-13` — "Fringe" event tag + "Edinburgh Fringe Festival productions." description. Keep (real festival taxonomy).
- `db/seeds/content.rb:51-52,145-150` — Fringe volunteer opportunity + "Edinburgh Fringe" get-involved page seed. Keep (real content).
- `app/views/static/contact/fringe.html.erb:1` — "Contact Fringe" static page. Keep (real Fringe contact page).

(All `test/**`, `docs/**`, `plans/**` fringe hits are fixtures/specs/docs — not shipped copy; excluded from the fix set but visible in the raw grep above.)

---

## TASK B — Em dashes (U+2014) in user-facing copy

`config/locales/**` has **zero** em dashes. Below, "user-facing" = rendered to a user (view text, page `@title`, flash, email body/subject, status-page detail, form validation message, JS toast). Everything I classify as NOT user-facing (ERB `<%# %>` comments, Ruby `#` comments, `Rails.logger.*`, `log_and_notify`, `@io.puts`, CSS comments) is listed separately at the end so you can confirm.

### B1. User-facing prose — recommend rewrite

| # | file:line | Current (surrounding) | Proposed rewrite |
|---|-----------|------------------------|------------------|
| 1 | `app/views/admin/reimbursements/expenses/edit.html.erb:3` | `This claim is a draft — only you can see it. Finish it and submit it below.` | `This claim is a draft. Only you can see it. Finish it and submit it below.` |
| 2 | `app/views/admin/reimbursements/expenses/_form.html.erb:41` | `This claim is a draft — only you can see it. <strong>Submit expense</strong> sends it to the` | `This claim is a draft. Only you can see it. <strong>Submit expense</strong> sends it to the` |
| 3 | `app/views/admin/reimbursements/expenses/_form.html.erb:59` | `Please re-attach your receipt below — check the errors above, then submit again.` | `Please re-attach your receipt below. Check the errors above, then submit again.` |
| 4 | `app/views/admin/reimbursements/expenses/_form.html.erb:94` | `That's a large claim. Please double-check the amount is right — a common slip is` | `That's a large claim. Please double-check the amount is right; a common slip is` |
| 5 | `app/views/admin/reimbursements/settings/edit.html.erb:47` | `These steps need Microsoft 365 admin permissions (Exchange Online / SharePoint admin) —` | end the sentence after the parenthetical: `…(Exchange Online / SharePoint admin).` (join with following clause as a new sentence) |
| 6 | `app/views/admin/reimbursements/settings/edit.html.erb:157` | `Pick at least one day — the nightly can't be turned off by unchecking them all.` | `Pick at least one day; the nightly can't be turned off by unchecking them all.` |
| 7 | `app/views/admin/reimbursements/batches/index.html.erb:15` | `…and hasn't finished — it has likely` | `…and hasn't finished; it has likely` |
| 8 | `app/views/admin/reimbursements/batches/index.html.erb:22` | `Its EUSA draft will appear below when ready — don't rebuild in the meantime.` | `Its EUSA draft will appear below when ready. Don't rebuild in the meantime.` |
| 9 | `app/views/admin/reimbursements/batches/index.html.erb:28` | `<strong>failed</strong> —` | restructure to end the sentence / use a colon: `<strong>failed</strong>:` |
| 10 | `app/views/admin/reimbursements/batches/index.html.erb:41` | `…found no Approved expenses —` | `…found no Approved expenses.` (new sentence) |
| 11 | `app/views/admin/reimbursements/batches/index.html.erb:49` | `failed — the EUSA draft is fine, check these before filing the batch away:` | `failed. The EUSA draft is fine; check these before filing the batch away:` |
| 12 | `app/views/admin/reimbursements/batches/index.html.erb:84` | badge `"No EUSA draft — needs a look"` | `"No EUSA draft: needs a look"` |
| 13 | `app/views/admin/reimbursements/batches/show.html.erb:14` | badge `"No — needs a look"` | `"No: needs a look"` |
| 14 | `app/views/admin/reimbursements/batches/show.html.erb:22` | badge `"No — needs a look"` | `"No: needs a look"` |
| 15 | `app/views/admin/reimbursements/reconcile/apply.html.erb:7` | `row<%= "s" unless … %> hit a problem — everything else below` | `row… hit a problem; everything else below…` |
| 16 | `app/views/reimbursements/emails/batch_ready.html.erb:46` | `other steps hit a problem — please check before assuming everything else completed` | `other steps hit a problem. Please check before assuming everything else completed` |
| 17 | `app/views/admin/reimbursements/budgets/index.html.erb:65` | title `("Over budget — nothing left to spend" if …)` | `"Over budget: nothing left to spend"` |
| 18 | `app/views/admin/reimbursements/my_budgets/index.html.erb:41` | `#<%= expense.auto_number %> — <%= expense.effective_payee_name %>` | `#<%= expense.auto_number %>: <%= expense.effective_payee_name %>` |
| 19 | `app/views/admin/reimbursements/review/_expense_card.html.erb:32` | `#<%= expense.auto_number %> — <%= expense.person&.name.presence \|\| "(no payee)" %>` | `#<%= … %>: <%= expense.person&.name… %>` |
| 20 | `app/views/admin/reimbursements/expense_edits/edit.html.erb:12` | `#<%= @expense.auto_number %> — <%= @expense.person&.name.presence \|\| "(no payee)" %>` | `#<%= … %>: <%= … %>` |
| 21 | `app/views/admin/reimbursements/expenses/show.html.erb:40` | `<%= @expense.effective_payee_name %> —` (bank line: `Name — sortcode / acct`) | use a comma/pipe: `<%= effective_payee_name %>,` or `… |` |
| 22 | `app/views/owner_endorsement_digest_mailer/digest.text.erb:6` | `- #<%= expense.auto_number %> — <%= expense.budget&.name %>` | `- #<%= expense.auto_number %>: <%= expense.budget&.name %>` |
| 23 | `app/views/admin/opportunities/show.html.erb:5` | `label += " — #{role.department.name}"` (role list: `Position — Dept`) | `label += ": #{role.department.name}"` (or ` (#{…})`) |
| 24 | `app/views/admin/opportunities/_form.html.erb:19` | select `include_blank: "— None —"` | `"None"` (drop decorative dashes) |
| 25 | `app/views/admin/opportunities/_form.html.erb:69` | select `include_blank: "— Me / external —"` | `"Me / external"` |
| 26 | `app/views/admin/opportunities/_form.html.erb:64` | `…of an external submitter — you will be recorded as having created it on their behalf.` | `…of an external submitter. You will be recorded as having created it on their behalf.` |
| 27 | `app/views/admin/permissions/role_grid.html.erb:1` | title `"Permissions — #{@role.name}"` | `"Permissions: #{@role.name}"` |
| 28 | `app/views/admin/duplicates/index.html.erb:24` | title `"Definite Duplicates (Same Student/Associate ID) — #{…} group(s)"` | `"… (Same Student/Associate ID): #{…} group(s)"` |
| 29 | `app/views/admin/duplicates/index.html.erb:67` | `"Likely Duplicates (Name Match + Overlapping Activity) — #{…} pair(s)"` | `"…: #{…} pair(s)"` |
| 30 | `app/views/admin/duplicates/index.html.erb:119` | `"Possible Duplicates (Name Match, Different Time Periods) — #{…} pair(s)"` | `"…: #{…} pair(s)"` |
| 31 | `app/views/admin/duplicates/index.html.erb:171` | `"Fuzzy Name Match (Both Names) — Overlapping Years — #{…} pair(s)"` | `"Fuzzy Name Match (Both Names), Overlapping Years: #{…} pair(s)"` (two dashes) |
| 32 | `app/views/admin/duplicates/index.html.erb:223` | `"Fuzzy Name Match (Both Names) — No Overlapping Years — #{…} pair(s)"` | `"Fuzzy Name Match (Both Names), No Overlapping Years: #{…} pair(s)"` (two dashes) |

#### Ruby string literals rendered to users

| # | file:line | Current | Proposed rewrite |
|---|-----------|---------|------------------|
| 33 | `app/helpers/reimbursements_helper.rb:151` | `"Only you can see this — submit it when you're ready."` | `"Only you can see this. Submit it when you're ready."` |
| 34 | `app/helpers/reimbursements_helper.rb:153` | `"Checked and approved — waiting to be sent to EUSA for payment."` | `"Checked and approved; waiting to be sent to EUSA for payment."` |
| 35 | `app/helpers/reimbursements_helper.rb:156` | `"Not approved — see the reason on the row."` | `"Not approved. See the reason on the row."` |
| 36 | `app/models/reimbursements/expense_form.rb:189` | validation: `"and account number — not just one or two."` | `"and account number, not just one or two."` |
| 37 | `app/controllers/admin/reimbursements/expense_edits_controller.rb:262` | `"and account number — not just one or two."` (dup of #36) | `"and account number, not just one or two."` |
| 38 | `app/services/reimbursements/ai_checker.rb:43` | `error_result("No receipts attached — cannot perform AI check.")` | `"No receipts attached, so the AI check can't run."` (or `: cannot perform…`) |
| 39 | `app/services/reimbursements/batch_processor.rb:248` | `"SUBMIT FAILED — DOUBLE-DRAFT RISK: could not mark expense …"` (operator error list) | `"SUBMIT FAILED (DOUBLE-DRAFT RISK): could not mark expense …"` |
| 40 | `app/services/reimbursements/batch_processor.rb:268` | `"…draft — send THIS existing draft and repair the batch record manually. DO NOT rebuild."` | `"…draft. Send THIS existing draft and repair the batch record manually. DO NOT rebuild."` |
| 41 | `app/services/reimbursements/batch_processor.rb:320` | `"…#{WRITE_RETRY_ATTEMPTS} attempts — their notification email was already sent, so a …"` | `"…#{…} attempts; their notification email was already sent, so a …"` |
| 42 | `app/services/reimbursements/bacs_xlsx.rb:69` | `TemplateError`: `"…#{MAX_ROWS}-row capacity — …"` (operator-visible exception) | `"…#{MAX_ROWS}-row capacity. …"` |
| 43 | `app/services/reimbursements/notifier.rb:68` | subject `"— #{run_date}"` (continuation, `… submitted for payment — DATE`) | `": #{run_date}"` |
| 44 | `app/services/reimbursements/notifier.rb:79` | subject `"[Bedlam BACS] Manual review needed — #{count} … "` | `"[Bedlam BACS] Manual review needed: #{count} …"` |
| 45 | `app/services/reimbursements/notifier.rb:80` | subject `"— #{run_date}"` | `": #{run_date}"` |
| 46 | `app/services/reimbursements/notifier.rb:95` | subject `"— #{run_date}"` | `": #{run_date}"` |
| 47 | `app/services/reimbursements/notifier.rb:110` | subject `"[Bedlam BACS] Draft ready — #{count} … "` | `"[Bedlam BACS] Draft ready: #{count} …"` |
| 48 | `app/services/reimbursements/notifier.rb:111` | subject `"— #{run_date}"` | `": #{run_date}"` |
| 49 | `app/services/reimbursements/notifier.rb:122` | subject `"[Bedlam BACS] Batch processing FAILED — #{run_date}"` | `"[Bedlam BACS] Batch processing FAILED: #{run_date}"` |
| 50 | `app/controllers/admin/reimbursements/people_controller.rb:47` | flash: `"#{@person.name}'s bank details fail the modulus check — fix them …"` | `"…fail the modulus check. Fix them …"` |
| 51 | `app/controllers/admin/reimbursements/reconcile_controller.rb:52` | flash: `"Nothing to apply — start again from the paste step."` | `"Nothing to apply. Start again from the paste step."` |
| 52 | `app/controllers/admin/reimbursements/reconcile_controller.rb:59` | flash: `"Could not parse the actuals — start again from the paste step."` | `"Could not parse the actuals. Start again from the paste step."` |
| 53 | `app/controllers/admin/reimbursements/settings_controller.rb:44` | `@title = "Settings — #{@cost_centre.name}"` | `"Settings: #{@cost_centre.name}"` |
| 54 | `app/controllers/admin/reimbursements/settings_controller.rb:57` | `@title = "Settings — #{@cost_centre.name}"` | `"Settings: #{@cost_centre.name}"` |
| 55 | `app/controllers/admin/reimbursements/settings_controller.rb:81` | `@title = "Settings — #{@cost_centre.name}"` | `"Settings: #{@cost_centre.name}"` |
| 56 | `app/controllers/admin/reimbursements/settings_controller.rb:114` | flash: `"… — please pick it again."` | `"…. Please pick it again."` (restructure to end prior clause) |
| 57 | `app/controllers/admin/reimbursements/batches_controller.rb:86` | flash: `"…emailed to you when ready — don't rebuild it in the meantime."` | `"…emailed to you when ready. Don't rebuild it in the meantime."` |
| 58 | `app/controllers/admin/reimbursements/batches_controller.rb:153` | flash: `"…do not reopen — repair reconciliation …"` | `"…do not reopen; repair reconciliation …"` |
| 59 | `app/controllers/admin/reimbursements/budgets_controller.rb:28` | `@title = "Budget — #{@budget.name}"` | `"Budget: #{@budget.name}"` |
| 60 | `app/controllers/admin/reimbursements/finance_controller.rb:71` | `"That budget no longer exists — please pick another."` | `"That budget no longer exists. Please pick another."` |
| 61 | `app/controllers/admin/reimbursements/finance_controller.rb:78` | `"One or more selected owners no longer exist — please update the list."` | `"…no longer exist. Please update the list."` |
| 62 | `app/controllers/admin/reimbursements/status_controller.rb:57` | Check detail: `"Reachable — read #{count} budget(s)."` | `"Reachable: read #{count} budget(s)."` |
| 63 | `app/controllers/admin/reimbursements/status_controller.rb:60` | detail: `"#{e.message}. This needs IT — the Airtable token or base id …"` | `"#{e.message}. This needs IT: the Airtable token or base id …"` |
| 64 | `app/controllers/admin/reimbursements/status_controller.rb:69` | detail: `"Reachable — acquired an app token."` | `"Reachable: acquired an app token."` |
| 65 | `app/controllers/admin/reimbursements/status_controller.rb:72` | detail: `"…client secret may have expired — contact IT …"` | `"…may have expired. Contact IT …"` |
| 66 | `app/controllers/admin/reimbursements/status_controller.rb:89` | detail: `"No API key set — AI checks are disabled."` | `"No API key set. AI checks are disabled."` |
| 67 | `app/controllers/admin/permissions_controller.rb:25` | `@title = "Permissions — #{@role.name}"` | `"Permissions: #{@role.name}"` |
| 68 | `app/controllers/admin/debt_checkers_controller.rb:21` | `@title = "Debt Check — #{@user.name_or_email}"` | `"Debt Check: #{@user.name_or_email}"` |
| 69 | `app/models/admin/staffing_job.rb:97` | calendar `event.summary = "#{staffable.show_title} — #{name}"` | `"#{staffable.show_title}: #{name}"` |

#### JavaScript (user-facing toasts/status)

| # | file:line | Current | Proposed rewrite |
|---|-----------|---------|------------------|
| 70 | `app/javascript/controllers/reimbursements_receipt_controller.js:77` | `"Kept the receipt you attached — check the errors above and submit again."` | `"Kept the receipt you attached. Check the errors above and submit again."` |
| 71 | `app/javascript/controllers/bulk_review_controller.js:46` | `…flagged as needing attention — check the reasons on the card${…` | `…flagged as needing attention. Check the reasons on the card${…` |

### B2. User-facing "empty value" placeholder em dashes — judgment call

These render a bare `"—"` as a "no value" glyph (not prose). Note the inconsistency: `app/helpers/reimbursements_helper.rb:84`'s comment states nil should render `"-"` (hyphen), yet these views hardcode `"—"`. Recommend standardising — either a shared `"–"`/`"-"`/`"None"` or a helper — but this is your call, not clearly "prose em dash":

- `app/views/admin/reimbursements/budgets/index.html.erb:36` — `content_tag(:span, "—", class: "text-gray-400")`
- `app/views/admin/reimbursements/expenses/show.html.erb:23` — `@expense.budget&.name || "—"`
- `app/views/admin/reimbursements/expenses/show.html.erb:24` — `@expense.payment_reference.presence || "—"`
- `app/views/admin/reimbursements/expenses/show.html.erb:33` — `@expense.description.presence || "—"`
- `app/views/admin/reimbursements/expenses/show.html.erb:41` — `effective_sort_code.presence || "—"`
- `app/views/admin/reimbursements/expenses/show.html.erb:42` — `effective_account_number.presence || "—"`

### B3. NOT user-facing — excluded (reported for confirmation)

These em dashes are in comments, logs, or non-rendered data. No change recommended, but listed so you can decide:

- **`prompt_safety.rb:22`** — `DASH_LIKE = "-‐‑‒–—―−－─"` — the em dash here is **data** (a dash-normalisation char class for AI-prompt sanitising). Must NOT be removed.
- **ERB `<%# … %>` / Ruby `#` comments in views:** `app/components/admin/search_form_component.html.erb:5`; `app/views/admin/users/_merge_modal.html.erb:11,12`; `app/views/shared/_search_form.erb:8`; `app/views/layouts/_alert_div.erb:7,14,15`; `app/views/layouts/reimbursements_mailer.html.erb:2`; `app/views/admin/reimbursements/reconcile/{show:4,preview:1,apply:1}`; `app/views/admin/reimbursements/expense_edits/{index:66,edit:21}`; `app/views/admin/marketing_creatives/categories/show.html.erb:6`; `app/views/admin/reimbursements/budgets/index.html.erb:28`; `app/views/admin/reimbursements/review/{index:13,_ai_verdict:2,3,_expense_card:12,216,223,241,_ai_verdict_body:15}`; `app/views/admin/reimbursements/expenses/{index:17,_form:10,140}`.
- **`app/views/shared/_image.erb:6,8`** — inside a `raise ArgumentError` / `Rails.logger.warn` (developer error, not shown to end users).
- **`Rails.logger.*` / `log_and_notify` / `@io.puts` strings:** `mailbox_poll_job.rb:169`; `airtable_importer.rb:154`; `build_batch_job.rb:61,72,91,122,137,140`; `nightly_batch_job.rb:67,235,241,245`; `reconcile_controller.rb:218,238`; `batches_controller.rb:126`; `rejects_expenses.rb:43`; `reimbursements_helper.rb:84` (comment). `airtable/config.rb:15` (config-error message — dev/boot-time, borderline; leave).
- **CSS/JS comments:** `app/javascript/entrypoints/application.css:58,100,162`; `app/javascript/styles/bootstrap_compat.css:229`; plus the many `config/initializers/*` and `app/javascript/entrypoints/admin.css` comment hits in the raw grep.
- **Repo docs / plans / CHANGELOG-style / this-repo markdown:** the bulk of the raw `rg '—'` output (`CLAUDE.md`, `docs/**`, `plans/**`, etc.) — internal, per your exclusion. Full dumps saved at the persisted-output paths if you want them.

---

**Scope summary:** Task A — 22 reimbursements "Fringe" hits to generalise (11 of them the same auto-reply/BACS sign-off pattern), plus 4 keep-as-comment and 4 legit-festival keeps app-wide. Task B — 71 user-facing prose em dashes to rewrite (32 view, 37 Ruby, 2 JS), 6 placeholder `"—"` glyphs as a judgment call, and the rest (comments/logs/docs) excluded. All read-only; nothing edited.

---

## Audit dev sending real emails

I have a complete picture. Here's my report.

---

### Root cause: the reimbursements Microsoft Graph mail path has NO environment gating

Standard ActionMailer is safe in dev/test, but reimbursements bypasses ActionMailer entirely and talks to Microsoft Graph directly — and that path fires real API calls (real replies to real people) in development.

#### 1. ActionMailer config — standard mailers are SAFE in dev and test

| Env | delivery_method | Notes |
|---|---|---|
| development | `:test` (`config/environments/development.rb:40`) | `raise_delivery_errors=false` (:35); `default_url_options` localhost:3000 (:43) |
| test | `:test` (`config/environments/test.rb:41`) | `default_url_options` www.example.com (:45) |
| production | `:smtp` → smtp.mailersend.net (`config/environments/production.rb:72-74`) | real |

So every `Mailer.…deliver_now/deliver_later` call (OpportunityMailer, UsersMailer, StaffingMailer, ReimbursementsMailer credential alerts, OwnerEndorsementDigestMailer, OpportunityDigestJob, DailyMaintenanceJob's TestMailer, etc.) goes to `ActionMailer::Base.deliveries` in dev/test — no real mail. That part is fine. No `letter_opener`/`mailcatcher` gem is present (not needed for safety; see recommendation).

#### 2. THE GAP — the Graph path is completely ungated

Reimbursements sends producer/operator/rejection emails and does mailbox reply/move via hand-rolled Graph API POSTs, not ActionMailer. I grepped every file in `app/services/reimbursements`, `app/jobs/reimbursements`, and the mailers for `Rails.env` / `production?` — **zero environment checks anywhere**:

- `Reimbursements::GraphClient#send_mail` (`app/services/reimbursements/graph_client.rb:99`) → `POST /users/{mailbox}/sendMail` — real send. Used by `Notifier` for rejection / payment-confirmation / producer / operator emails.
- `GraphClient#create_draft` (:55) → creates a real EUSA draft in the shared mailbox.
- `Reimbursements::MailboxClient#reply` (`app/services/reimbursements/mailbox_client.rb:59`), `#move` (:75), `#mark_read` (:68) → mutate the **real** shared mailbox and reply to real senders.
- `Reimbursements::GraphAuth#graph_request` (`app/services/reimbursements/graph_auth.rb:28`) and `#graph_raw_request` (:45) — the shared HTTP chokepoint, no env awareness.
- The only guard is `Settings.mailbox_configured?` (`app/services/reimbursements/settings.rb:34`) = credentials present, which is environment-agnostic. `Settings.raw_value` reads `ENV["REIMBURSEMENTS_*"]` first (:38-41).

#### 3. Dev exposure is real, not theoretical — recurring jobs fire in dev

- `config/puma.rb:38`: `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] || Rails.env.development?` — Solid Queue's full supervisor (dispatcher + worker + **recurring scheduler**) runs **inside Puma automatically in development**, i.e. every `bin/dev`.
- `config/recurring.yml` is **flat, not environment-scoped**, so its schedule applies to development too. `config/queue.yml` maps `development` to the default dispatcher (no `recurring_tasks: false`). Relevant entries:
  - `reimbursements_mailbox_poll` → `MailboxPollJob` **every 5 minutes**
  - `reimbursements_nightly_batch` → `NightlyBatchJob` 9pm daily
  - (`opportunity_digest`, `daily_maintenance`, `reimbursements_owner_endorsement_digest`, `reimbursements_credentials_check` all go through ActionMailer → `:test` → safe)
- `Settings` reads Azure creds from `ENV["REIMBURSEMENTS_AZURE_*"]` first. Per this project's own memory notes ("fnox env leaks into tests/dev"), a dev shell with fnox exports has **real** Azure credentials in ENV.

Result: running `bin/dev` in a fnox-exported shell → `MailboxPollJob` fires every 5 minutes → `Settings.mailbox_configured?` is true → it connects to the **real** shared mailbox, reads real unread mail, and **replies to real senders** ("this address isn't recognised" / "please attach a receipt" / "we've saved your draft"), marks them read and moves them (`MailboxPollJob#perform` at `app/jobs/reimbursements/mailbox_poll_job.rb:49-58`, handlers at :153-172, :205-217). `NightlyBatchJob` would email real operators. Additionally, a manager rejecting an expense in the dev admin UI hits `Notifier#rejection` → `GraphClient#send_mail` → real email to the real payee.

#### 4. Test env — mostly safe by convention, not construction

`config/environments/test.rb`: `queue_adapter = :test` (recurring jobs don't auto-fire) + mailer `:test`. Graph clients default to the real `HttpTransport`; tests stay safe only because they inject `FakeHttp`/fake clients via the `class_attribute` builder seams. Any test that builds a client without the seam in a fnox-leaked shell hits real Graph — the project already documents 3 such live-probing tests.

---

### Proposed fix — one flag, few guard points

Add a single `Settings.outbound_enabled?` flag (production-only, explicit opt-in elsewhere) and enforce it at the send chokepoints. This is more robust than an ActionMailer change because ActionMailer isn't the sending mechanism here.

**Patch A — the flag.** `app/services/reimbursements/settings.rb`, insert after the `backend` method (after line 22):

```ruby
    # Whether reimbursements may perform *outbound* Microsoft Graph side effects
    # — sending mail, replying to / moving mailbox messages, creating EUSA
    # drafts. Enabled only in production, unless explicitly opted in via
    # REIMBURSEMENTS_ENABLE_OUTBOUND (e.g. a staging box wired to a throwaway
    # mailbox, or the test suite which fakes the transport). Read-only Graph
    # probes (the Settings dashboard reachability checks) are NOT gated by this.
    def self.outbound_enabled?
      return true if Rails.env.production?

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"].present?
    end
```

**Patch B — stop the recurring poll in non-prod.** `app/jobs/reimbursements/mailbox_poll_job.rb:49-53`:

Before:
```ruby
    def perform
      unless Settings.mailbox_configured?
        Rails.logger.info("Reimbursements mailbox poll skipped: Graph credentials not configured")
        return
      end
```
After:
```ruby
    def perform
      unless Settings.outbound_enabled?
        Rails.logger.info("Reimbursements mailbox poll skipped: outbound disabled in #{Rails.env}")
        return
      end
      unless Settings.mailbox_configured?
        Rails.logger.info("Reimbursements mailbox poll skipped: Graph credentials not configured")
        return
      end
```

**Patch C — no-op the real send.** `app/services/reimbursements/graph_client.rb:99` (`send_mail`), first line of the method body:

Before:
```ruby
    def send_mail(mailbox:, to:, subject:, html:)
      graph_request(:post, "/users/#{mailbox}/sendMail",
```
After:
```ruby
    def send_mail(mailbox:, to:, subject:, html:)
      unless @settings.outbound_enabled?
        Rails.logger.info("Reimbursements send_mail suppressed (outbound disabled): to=#{Array(to).join(',')} subject=#{subject.inspect}")
        return nil
      end
      graph_request(:post, "/users/#{mailbox}/sendMail",
```
(`@settings` defaults to `Settings` — see the `initialize` at :45 — so this reads the flag through the same seam tests already use.) This covers every `Notifier` email (rejection, payment_confirmation, producer_notification, and all operator alerts including those NightlyBatchJob sends) plus BatchProcessor's EUSA email.

**Patch D — no-op draft creation.** `app/services/reimbursements/graph_client.rb:55` (`create_draft`), first line of the body:

Before:
```ruby
    def create_draft(mailbox:, to:, subject:, html:, attachments: [], cc: [])
      inline, large = Array(attachments).partition { |a| a.content.to_s.bytesize < INLINE_ATTACHMENT_LIMIT }
```
After:
```ruby
    def create_draft(mailbox:, to:, subject:, html:, attachments: [], cc: [])
      unless @settings.outbound_enabled?
        Rails.logger.info("Reimbursements create_draft suppressed (outbound disabled): to=#{Array(to).join(',')}")
        return Draft.new(id: "suppressed-#{SecureRandom.hex(4)}", web_link: "")
      end
      inline, large = Array(attachments).partition { |a| a.content.to_s.bytesize < INLINE_ATTACHMENT_LIMIT }
```

**Patch E — let the (faked-transport) test suite still exercise this logic.** `test/test_helper.rb`, right after line 31 (`ENV["REIMBURSEMENTS_BACKEND"] = "database"`):

```ruby
# Outbound Graph sends/replies are gated to production (Settings.outbound_enabled?).
# Tests fake the HTTP transport, so opting in here exercises the send/poll logic
# without any real network call.
ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = "1"
```

This mirrors the existing backend-forcing pattern and keeps the `MailboxPollJob` / `Notifier` / `NightlyBatchJob` tests green while making dev safe by default.

#### Notes / caveats on the patch

- **`NightlyBatchJob` is transitively covered** by Patch C (all its output is `Notifier#send_mail`). Optionally add the same `outbound_enabled?` early-return at its `perform` (`app/jobs/reimbursements/nightly_batch_job.rb:46`) to skip the work entirely and keep dev logs clean — not required for safety.
- **`MailboxClient#reply/move/mark_read`** are reached only inside `MailboxPollJob`, so Patch B fully protects them for the recurring path. If you want belt-and-braces against someone driving `MailboxClient` from a dev `rails console`, add the same `@settings.outbound_enabled?` guard to `reply`/`move`/`mark_read` in `mailbox_client.rb` — but note `find_or_create_folder` does a GET then POST, so a blanket verb-level block inside `GraphAuth#graph_request` is *not* recommended (the POST returning `{}` would make `.fetch("id")` raise). Gating the semantic methods (Patches B–D) is cleaner.
- **Read-only Graph probes stay working in dev** (the Settings integration-status dashboard: `check_reachable`, `check_mailbox` — all GET), which is desirable.

#### letter_opener recommendation

**Optional, not a safety fix.** ActionMailer is already `:test` in dev, so no real mail escapes via mailers. Adding `letter_opener` to the Gemfile `:development` group + setting `config.action_mailer.delivery_method = :letter_opener` in development.rb only improves the *preview* experience (opens sent mail in the browser instead of it vanishing into `deliveries`). It does nothing for the actual gap, which is the Graph path above. I'd treat it as a nice-to-have separate from this dev-safety fix.

---

## Design new cost-centre form

I have everything needed. Here is the complete scoping.

### Current-state findings

**A `CostCentre` AR model already exists** — no new model or table is required. `app/models/reimbursements/cost_centre.rb` maps to `reimbursements_cost_centres`, a modern **bigint-PK** table (schema annotation lines 6-22), so the legacy-integer-PK caveat does not apply. It was created by `db/migrate/20260710120000_create_reimbursements_cost_centres.rb` (+ three follow-up migrations for SharePoint/nightly columns).

**The gap is purely UI**: cost centres can currently only be created by seeds (`db/seeds/reimbursements.rb`) or console. The admin surface is `Admin::Reimbursements::SettingsController` (`app/controllers/admin/reimbursements/settings_controller.rb`), routed as `resources :settings, only: %i[index edit update], param: :key` (`config/routes.rb:146-148`). Its `#index` lists cost centres and links to `#edit`; there is **no `new`/`create`**. So "add a cost centre form" = add `new`/`create` to this existing controller.

**Required fields for a valid row** (model validations, lines 51-64): `key` (unique, used as the URL param), `name`, `eusa_code` (unique), `receive_mailbox` + `send_mailbox` (unique, `URI::MailTo::EMAIL_REGEXP` format). `nightly_run_days` defaults to `[2,4]`. Everything else (SharePoint drive/folder ids, site URL, `eusa_recipient`, `eusa_signature_name`) is optional and already editable on the existing `#edit` page — so the **new** form should collect only the 5 required fields and redirect to `#edit` for the rest.

**Form convention note**: despite CLAUDE.md mentioning simple_form generally, the reimbursements views do **not** use simple_form — `settings/edit.html.erb` uses plain `form_with model:` + Tailwind-classed `f.text_field` + `f.submit ..., class: btn_classes(:primary)`. Mirror that exact style, not simple_form.

### Closest CRUD to mirror

`SettingsController` / `settings` views themselves — same model, same `reimbursements_finance` permission gating (via `FinanceController < BaseController`, `authorize! :manage, :reimbursements_finance`). No per-model CanCan is used.

### Permission-grid handling

`Reimbursements::CostCentre` is **absent from the exclusion list** in `Admin::PermissionsController#set_models_and_roles` (`app/controllers/admin/permissions_controller.rb:85-88`) — meaning it currently auto-appears in the grid as a top-level model, unlike every sibling (`Budget`, `Person`, `Expense`, … are all excluded). Since the form is gated by the `reimbursements_finance` misc permission (not per-model abilities), **add `Reimbursements::CostCentre` to that exclusion array** for consistency. This is a pre-existing inconsistency the feature should tidy up; it needs no `Ability` change.

### Exact change set

**Modify — route** (`config/routes.rb:146`):
```ruby
resources :settings, only: %i[index new create edit update], param: :key do
```
(`new`/`create` are collection-level, so they ignore the `:key` param — fine.)

**Modify — controller** (`app/controllers/admin/reimbursements/settings_controller.rb`): add `new` (builds `::Reimbursements::CostCentre.new`), `create` (permit `:key, :name, :eusa_code, :receive_mailbox, :send_mailbox`; on save redirect to `edit_admin_reimbursements_setting_path(cc.key)` with a "now configure mailboxes/SharePoint" notice; on failure re-render `:new` with `flash.now[:alert] = errors.full_messages.to_sentence`, `status: :unprocessable_entity` — mirroring `save_settings`, lines 77-85).

**Create — view** `app/views/admin/reimbursements/settings/new.html.erb`: a `CardComponent` wrapping `form_with model: @cost_centre, scope: :cost_centre, url: admin_reimbursements_settings_path` with 5 Tailwind-classed `f.text_field`s and `f.submit "Create cost centre", class: btn_classes(:primary)`. Mirror the markup of `settings/edit.html.erb` lines 7-20.

**Modify — index entry point** `app/views/admin/reimbursements/settings/index.html.erb`: add a `link_to "New cost centre", new_admin_reimbursements_setting_path, class: btn_classes(:primary, :sm)` (or `get_link` if preferred) above/below the card. Optionally add a matching sidebar item in `app/helpers/navigation_helper.rb` (not required — the index is the natural entry point).

**Modify — permissions** `app/controllers/admin/permissions_controller.rb`: add `Reimbursements::CostCentre` to the subtracted array (line 85-88).

**Test — functional** `test/functional/admin/reimbursements/settings_controller_test.rb` (existing file): add `get :new` renders, `post :create` with valid params creates a row + redirects to edit, invalid params (blank/duplicate `key` or `eusa_code`, malformed mailbox) re-renders `:new` with no row created. The setup block (lines 54-62) already wires the `reimbursements_finance` role. Note: there is **no** `create_reimbursements_cost_centre` helper in `test/support/reimbursements_test_helpers.rb` — tests get a cost centre from the fixture `test/fixtures/reimbursements/cost_centres.yml` (`fringe`); build create params inline.

**Test — system** `test/system/admin/reimbursements/finance_js_test.rb` (existing file): a plain form-render + fill + submit test is safe here — this form has **no markdown editor**, so the Playwright/Selenium `fill` caveat from CLAUDE.md does not apply.

### Open questions

1. **Field set**: confirm the new form should collect only the 5 required fields (key, name, eusa_code, receive_mailbox, send_mailbox) and defer SharePoint/nightly/EUSA-recipient to the existing edit page. That's the natural split, but you may want `eusa_recipient`/`eusa_signature_name` on the create form too.
2. **`key` input**: `key` is a URL slug (`param: :key`, `find_by!(key:)`). Should the operator type it freely, or should it be auto-derived from `name` (e.g. `acts_as_url` like `Company`) to avoid spaces/uppercase in URLs? Currently it's a free string with only a uniqueness validation — no format/slug enforcement exists. Recommend either a slug format validation or auto-derivation.
3. **No "active/archived" flag exists** on `CostCentre` — the backlog item only asks to *add*, so no delete/deactivate is in scope, but worth confirming there's no need to retire a cost centre later.

