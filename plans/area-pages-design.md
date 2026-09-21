# Area pages: what an owner sees, and where finance manages one area

Design of 2026-09-21, from Mick's choices (inbox + area pages; one shared area page; plain words
with finance terms on hover) and a read-only profile of production. Build starts after the
audit's group-1 budget fixes merge, because this sits on the corrected `Budget#remaining` and the
single forecast label. Audit: [finance-ux-audit.md](finance-ux-audit.md).

## Can an owner see their budgets today?

Barely. `my_budgets#index` lists one card per owned **line** showing `Remaining` only, and only
when a forecast was logged (35 of 96 production lines). No budget figure, no spend, no claims
other than the ones awaiting sign-off, no area, income and inactive lines hidden. Areas have no
show page at all: finance gets an index row and an edit form whose nested lines carry no money.

## The decisions these screens serve

- **Owner, landing page:** "Is anything waiting on me, and is any of my shows in trouble?"
- **Owner, area page:** "Can my show afford this, and where has claim #n got to?"
- **Finance, area page:** "What is going on with this show, and what do I need to change?"

## What production looks like (2026-09-21)

| Fact | Figure | Design consequence |
|---|---|---|
| Areas | 60; **53 name no owner**, 7 name one | Most areas are finance-only pages. The ownerless state (sign-off switched off) is the norm and must say so plainly, with the fix one click away |
| Owners | 7 people, 1–2 areas each (5 also own 1–3 loose lines), all with a linked account | Landing page is 1–4 rows. No search, no pagination |
| Endorsements | 7, **all finance overrides**; 0 of 2 pending claims await an owner | No owner has ever signed off. The inbox is empty by default: its empty state is the state |
| Lines per area | median **1**, p95 2, max 4 | The lines table is usually one row. Single-line area whose line shares its name ("Tech"/"Tech") prints the name once |
| Claims per area | median 0, p95 19, max 59 | Status tabs + 25 per page. The zero-claims state is the median |
| Agreed total | nil on 6 areas; **£0.00 on many termtime areas**; £100 on "Tech" against £2,526 spent | See "No budget" below |
| Lines with no initial budget | 38 of 96; no forecast 65 of 96 | "Left" needs the fallback the audit fix adds; with neither figure it says "no budget set" |
| Areas over | 11 of 60 | Over-budget is common: a badge and a red figure, not an alarm banner |
| Names | area p95 20 / max 39 chars; `display_name` max 80 | Headings wrap; table name cell wraps; nothing truncates |
| Duplicate names | two areas called "Tech" (different year/centre) | Landing rows and the page heading always carry centre and year |
| Claim descriptions | median 18, p95 44, max 83 chars | One line in the claims table, wrapping |
| Rail / type | all UK BACS; 197 reimbursements, 42 invoices | Type badge earns a column; rail only when international |

### "No budget" is three different states

1. **No agreed total, lines have budgets** (Improverts: lines sum to £2,700, £2,301 spent).
   Comparator falls back to the line sum, labelled: "No total agreed. Its lines add up to £2,700."
2. **Agreed total £0, nothing allocated, real spend** (Last years business: £3,273 spent). A £0
   cap with spend against it is almost certainly "nobody set one", not an overspend. Show "£3,273
   spent · no budget set", no red, and (finance only) "Set an agreed total".
3. **A real total that is exceeded** (Tech: £100 vs £2,526). Red, "£2,426 over".

Rule (Mick, 2026-09-21): an agreed total of 0 with nothing allocated is "no budget set". One
predicate on the model, shared with the Budgets index and Overview badges.

## Vocabulary

| On screen | Finance term (hover + glossary) | Source |
|---|---|---|
| Budget | Projected: latest forecast, else initial | `projected_amount` |
| Spent | Committed: approved + sent to EUSA + paid, ex-VAT | `committed_amount` |
| Waiting for approval | Pipeline: pending claims | `pipeline_amount` |
| Left | Remaining | `remaining` |
| Agreed total / Not yet given to a line | Agreed total / Unallocated | `Area#projected_amount`, `#unallocated` |

A footnote on both pages: "Figures exclude VAT, so they can be lower than the amounts claimed."

## Screen 1: My Budgets (landing)

```
MY BUDGETS
Waiting for your sign-off
  Nothing is waiting on you.  Claims on your shows appear here when someone submits one;
  you'll also get an email on finance's reminder days.

Your shows and budgets                         Budget    Spent   Waiting      Left
  Improverts · Fringe 2026          3 lines    £2,700   £2,301       £0      £399   >
     no total agreed; lines add up to £2,700
  Tech · Termtime 2026/27           1 line       £100   £2,526       £0   £2,426 over  >
  Tech · Fringe 2026                2 lines        …
  Consumables (single budget)                    £150       £9       £0      £141   >
```

With claims waiting, the inbox lists them across all areas (number, submitter, amount, line,
days waiting, receipt, Endorse / Reject), exactly the actions the cards have today.

## Screen 2: the area page (`areas#show`), shared

Owners see it read-only plus their sign-off buttons. Finance sees the same page with actions.
A loose line gets the same page shape at `budgets#show` (same partials; no lines table).

```
< My budgets  (owner)   |   < All areas  (finance)
IMPROVERTS · Fringe 2026 · spend cap                     [Edit area] [Add line] [Revise total]
Owners: A. Owner    (none: "Nobody owns this show, so claims skip sign-off. [Add an owner]")

  Budget £2,700* | Spent £2,301 | Waiting £0 | Left £399
  [==================------]   * no total agreed; this is what its lines add up to

  Lines          Code     Budget    Spent  Waiting     Left
   Marketing     432320   £1,100     £692       £0     £408        [Revise] [Edit]
   Retreat       432980   £1,500   £1,512       £0   £12 over      [Revise] [Edit]
   Other         432320     £100      £97       £0       £3        [Revise] [Edit]

  Claims   [All 21] [Waiting 0] [Approved 1] [With EUSA 12] [Paid 8]
   #231  With EUSA  J. Smith   £64.20  Marketing  Flyers            12 Sep   >
   …25 per page

  Changes to the budget (finance sees who; owners see date, amount, reason)
   14 Jun  Marketing £600 -> £1,100  "extra print run agreed"
```

- Claim rows link to the finance edit page for finance, and to the producer show page when the
  viewer submitted it; otherwise they are not links (an owner may view the receipt, as today).
- Income lines sit in their own small table ("expected / received"), never summed with spend.
- URL state: `?status=` for the claims tab, `?page=`.

## States to build and test

| State | Record |
|---|---|
| Typical | one-line termtime area, 0 claims, no budget set |
| Busy | Last years business: 59 paid claims, one line, £0 total |
| Partial | Improverts: no total, three budgeted lines, one over by £12 |
| Over | Tech: £100 vs £2,526 |
| Empty | Nativity: £120 agreed, no lines, no claims ("No lines yet. [Add line]") |
| Ownerless | 53 of 60 |
| Stress | two areas named "Tech" on one owner's landing page; an 80-character line name; an owner whose only area is inactive but still has a pending claim |
| Not yours | a non-owner, non-finance user opening an area URL gets a 404, as receipts do |

## Access

`areas#show` / `budgets#show`: finance, or a person in the area's (or loose line's) owner set.
Go through the store (`store.areas` for figures, per CLAUDE.md, never `budget.area`). Areas index
rows, the grouped Budgets index headings and the Overview's area headings all link here.

## Decisions and the approved mock

Mick approved the clickable mock on 2026-09-21: https://claude.ai/artifact/3G4ezy29kYHzB1SjABDUAL
(source in the gitignored `tmp/mocks/area-pages.html`). Build to it.

- Ownership will be used more later, so the inbox and the ownerless warning are both worth
  building properly even though 53 of 60 areas name nobody today.
- Built as mocked unless Mick says otherwise:
  - a claim sent to EUSA and not yet paid reads **"With EUSA"**;
  - **Left = Budget − Spent − Waiting**, so pending claims reduce it. The portal's `remaining`
    ignores pending, so this is a new derived figure with its own name in code, not a change
    to `Budget#remaining`;
  - an owner sees every claim on their area (number, status, amount, line, description, date,
    batch) and never bank details.

