# Finance portal: what is left to fix

> **DONE, 2026-09-22.** Every item below shipped on the `finance-ux-next` branch: the finance
> home page, the EUSA draft link and its unsent probe, all three undo gaps (ledger unlink and
> re-pair, claim payee and reopen-rejected, budget updates opened and undone), the glossary, and
> all twelve of "the rest". The evidence for each is in its own commit message; the traps worth
> keeping went into CLAUDE.md. Kept as the record of what the audit asked for and why.


Handover, 2026-09-21. The audit is [finance-ux-audit.md](finance-ux-audit.md) and the area-page
design is [area-pages-design.md](area-pages-design.md); read the audit's "Findings by task"
section for the evidence behind any item below, and CLAUDE.md's "Reimbursements portal" section
before touching the code — it is dense and nearly all of it is traps.

## What has already shipped

Merged to `main` and deployed on 2026-09-21: every item of the audit's group 0 (the screens that
said things that were not true), all ten of group 1, plus three things not on that list — the
area page, the My Budgets rebuild, and the Finance sidebar regroup. Do not redo these.

The two rules an owner decided, which the rest of the work must keep:

- **A plan of exactly £0 with nothing allocated is "no budget set", never a cap of nothing.**
  `Reimbursements::PlannedAmount#no_budget_set?`, included by Budget and Area. Production carries
  many termtime areas in that state with real spend against them.
- **`Left` is budget less spent AND waiting** (`Reimbursements::SpendSummary`), which is
  deliberately not `Budget#remaining` / `Area#remaining` — those ignore the pipeline because
  finance needs them to. Both readings are wanted; neither replaces the other.

## What is left, in the order I would do it

### 1. A finance home page (audit item 11)

`/admin/reimbursements` redirects a finance user to `expenses#index` — their OWN claim list,
greeting the business manager with "Submit your expenses here". It is the single blocker behind
the handover task, which scored 1 out of 5 for a newcomer.

Land a small dashboard: claims awaiting approval, the approved-and-unbatched total, the last
batch and whether its draft still looks unsent, unlinked ledger rows, over-budget lines, the last
nightly run. Every figure already has a reader; this is assembly, not new arithmetic. Add the
matching `/admin` dashboard tile at the same time.

### 2. The EUSA draft link (audit item 14)

Batch history tells the operator "Its EUSA draft will appear below when ready" and Detail says
"EUSA draft created: Yes", and neither ever renders a link — `eusa_draft_web_link` reaches only
the operator email (`BuildBatchJob`), and `Batch` has no column for it. Sending that draft is the
one manual step left in paying people.

Store it on the batch and render it as the primary action. While there: History heads a batch
"Sent <date>" from a typed BACS date, and `BatchesController#reopen` already asks Graph whether
the draft is still unsent — surface that same probe as a status rather than only at reopen.

### 3. Undo the two things that cannot be undone (items 15, 16, 17)

- **Ledger:** no way to unlink a row from a wrongly matched claim or income line. The
  consequence is worse than it sounds: a credit reconcile attached whole to one income line is
  not `apportionable?`, so "Split across budgets" never appears on the row it was built for.
- **Claims:** finance can change a claim's rail now but not its payee, and a rejection is
  terminal — no control anywhere writes a status back to Pending.
- **Forecasts:** a budget update cannot be opened, corrected or undone as a unit
  (`routes.rb` gives it index/new/create only) and its log names the budgets revised but not the
  amounts.

### 4. Say what the words mean (item 13)

No glossary anywhere, and the portal's best explanations are `title=` tooltips, invisible on
touch and to the keyboard. Add one page defining the ten words the portal is built on — area,
cost centre, nominal code, actuals, offsetting pair, endorse, committed, pipeline, outturn,
variance — link it from every screen's intro paragraph, and put a visible "what these columns
mean" block on the budget screens plus a legend for the six People badges.

### 5. The rest

| # | Item |
|---|---|
| 12 (half) | The sidebar is regrouped, but `?year=` / `?cost_centre=` still do not survive a sidebar click — every nav href is bare |
| 18 | Exports page: sheet list, scope selectors, the scope stamped into the file, and Areas + forecast sheets (neither is exportable today) |
| 19 | Reconcile accepts an upload (it is paste-only, and the export arrives as an attachment) and says where that export comes from |
| 20 | New budget silently accepts an area from a different cost centre |
| 21 | Bulk override on the Awaiting owner tab |
| 22 | Integration Status: a send log with per-run counts — it cannot answer "did this person get their reminder" |
| 23 | The curated nominal-code labels feed nothing: the budget form's code is free text and the Overview prints bare digits |
| 24 | The area form's nested row cannot set a line's type or amount, so it lands as a £0 Expense line |
| 25 | Settings: move the PowerShell/IT section to its own page; nine buttons on it say "Save" |
| 26 | FX help on the GBP amount an international claim needs |
| 27 | A template editor for the EUSA covering email instead of a raw-HTML textarea (**attempted and reverted — read the note below before retrying**) |
| 28 | The expense import's docs and validation disagree about whether Payment reference is required |

**Item 27 was built and reverted** (`ad0d4461`, `d99ff601`, reverted by `ebd09724`). It replaced
the "Body (HTML)" textarea with a plain-text note plus `{{placeholders}}`, on the grounds that a
mistyped tag could silently break the claims table. Mick's ruling, and the constraints any second
attempt has to meet:

- **Editing the HTML has never mangled the table in practice.** The risk the change was built
  around was this audit's guess, not experience.
- **The table is a convenience for searching old email, not what EUSA pays from.** The figures
  they act on are in the BACS spreadsheet.
- **The whole email has to stay editable.** The note could only replace the OPENING paragraph,
  and that paragraph is the only place the batch total, the claim count and the "receipts are
  also attached" line are ever rendered — so any note at all sent EUSA a table with no stated
  total, and the form's preview rendered the note-LESS body, so the operator could not see it
  happen. It also removed every edit that is not the opening: a sentence after the table, a
  changed sign-off, a dropped row.

So a replacement must keep the full body editable, and if it generates any part of the message it
must generate the total and count OUTSIDE whatever the operator's text replaces.

Also open, from the mock review: the three defaults in
[area-pages-design.md](area-pages-design.md) ("With EUSA" as a label, pending claims counting
against Left, owners seeing every claim on their area) were built as designed and never
explicitly confirmed.

## How to work here

- **Tests go through `t`** (`~/.local/bin/t`), narrow targets while iterating, the full suite once
  at the end. `bin/rails test` is blocked by a hook. The laptop runs several Claude sessions at
  once and a full suite is ~1.4 GB.
- **Rebuild Vite after touching a Stimulus controller or a stylesheet** (`RAILS_ENV=test
  bin/vite build`), or roughly four tests fail with "Vite Ruby can't find entrypoints/admin.js"
  and look unrelated to what you changed.
- **The system suite is flaky under memory pressure on this machine** — different pairs fail each
  run and pass in isolation. Re-run the file alone before believing a failure.
- **Look at the rendered page.** Every screen here had a defect the tests could not see: the
  claims table 500ed because a ViewComponent gets no `paginate` helper and no test had rendered
  one with claims; the sticky area heading left a 20px gap at 1920px that rows scrolled through;
  a redirect anchor never reached the browser because Turbo drops the fragment. Measure sizes with
  `getBoundingClientRect`, do not eyeball them.
- Work in a provisioned worktree (`dev-hooks:worktree-setup`), commit atomically, and let the hk
  pre-commit hook run.
