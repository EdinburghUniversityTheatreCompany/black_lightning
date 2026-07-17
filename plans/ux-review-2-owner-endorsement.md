# UX review #2 — owner-endorsement feature + overall portal

Three persona agents (budget owner, finance administrator, overall/consistency) reviewed the
Phase E owner-endorsement feature and the wider reimbursements portal. Consolidated + de-duped
below, tiered by priority. Items marked **[decision]** are product choices to confirm before
building; everything else is a clear win.

## P1 — trust / correctness gaps

- **F1. Owners endorse semi-blind — no receipt, no full claim.** [decision: depth]
  My Budgets shows only payee / amount / 60-char description / date. The one artifact that
  justifies a sign-off — the receipt — is invisible, and there's no owner-accessible detail view
  (`find_own_expense!` is submitter-scoped). An owner can't endorse responsibly.
  *Two agents (owner P1, overall P2).*

- **F2. Owners can only Endorse — no reject / flag / guidance.** [decision: path]
  A bad claim can only be ignored (stalls silently, indistinguishable from not-yet-acted) or
  endorsed. No "this looks wrong" path and no copy telling the owner what to do. *Owner P1.*

- **F3. Bulk-approve summary mislabels an owner-gated skip** as "missing bank/budget/amount".
  `bulk_approve_summary` hard-codes that reason; a gated skip is silently mis-attributed.
  *Finance P1. (clear fix)*

- **F4. No positive "Endorsed by X" state on the finance review card**, so when a finance edit
  re-opens the gate (amount/budget changed → endorsement no longer covers) there's nothing tying
  the re-block to their edit — and `save` gives no feedback. *Finance P1.*

## P2 — should-fix

- **F5. "Needs attention" section copy omits the owner gate** and frames everything as "issues to
  fix" — but the gate isn't finance's to fix (owner endorses / finance overrides). Add the reason
  + soften the framing. *Finance + overall. (clear fix)*
- **F6. The gate wears advisory-yellow but is a hard block** (only overridable). Give it distinct
  weight / an explicit "(blocks approval until signed off or overridden)" qualifier. *Finance.*
- **F7. Reason line never names who must sign off / which budget** — finance can't tell whom to
  chase or whether the override case applies. Name the owners + budget. *Finance. (clear fix)*
- **F8. Override can't capture a justification** — the `note` column exists but there's no input,
  so `override_note` is always nil. Add an optional reason field. *Finance. (clear fix)*
- **F9. Override confirm doesn't state the consequence** ("paid without owner sign-off, recorded
  against you; use when no owner can sign off"). *Finance. (clear fix)*
- **F10. Stale endorsement silently shows a plain Endorse button again** (owner) / re-blocks
  (finance) with no "changed since you endorsed" explanation. *Owner + finance. (clear fix)*
- **F11. Digest re-sends to every co-owner with no "why / any one owner can clear this" footer** —
  reads as nagging and causes both-or-neither co-owner behaviour. Add a footer. *Owner. (clear fix)*
- **F12. Endorse is a one-click POST with no confirm and no undo.** Add a confirm; undo is a
  [decision]. *Owner.*
- **F13. Many-budget owner gets a wall of cards incl. empty ones, no summary.** Add a pending
  count + pending-first sort. *Owner. (clear fix)*
- **F14. Nav: non-finance producers see a category literally called "Finance"** containing only
  their 3 personal links. Split producer/owner-facing (Reimbursements / Payment Details / My
  Budgets) into their own category; keep finance-only tooling under Finance. *Overall P1. (clear fix)*
- **F15. Link/back-link colour drift** — `budgets/edit` uses raw `text-blue-700 hover:underline`
  instead of the `text-primary underline` token used elsewhere. *Overall. (clear fix)*

## P3 — polish / consistency

- **F16. Terminology drift** — claim / expense / reimbursement used interchangeably; endorse vs
  sign-off for the same action; nav labels vs page titles diverge. Pick a convention (producer =
  "claim", finance = "expense", action = "endorse") and align. *Overall + owner. (clear fix)*
- **F17. My Budgets intro copy**: "the finance team pays it" (EUSA pays, not finance); "cleared"
  double-duty vs the "Cleared by finance" badge; intro renders even for owners of nothing (move
  inside the non-empty branch). *Overall + owner. (clear fix)*
- **F18. "Cleared by finance" badge unexplained** to owners — add a tooltip. *Owner. (clear fix)*
- **F19. Table-header grey shade drift** across hand-rolled tables (`text-gray-500` vs `-600`).
  *Overall. (clear fix)*
- **F20. Disabled-Approve pattern differs** between hard blocks (shows disabled Approve) and the
  gate (only the override button) — minor inconsistency. *Finance P3.*

## Explicit design decisions to confirm
1. **F1 depth** — inline receipt lightbox per My Budgets row, vs a full read-only owner claim view.
2. **F2 path** — guidance copy only / a "flag for finance" action / a full owner reject.
3. **F12 undo** — allow an owner to withdraw an endorsement while the claim is still Pending?
