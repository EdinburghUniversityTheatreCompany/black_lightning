# Admin form consistency review (2026-09-05)

**Status: implemented on the `form-unify` branch, 2026-09-06.** Every defect below is fixed; the
"Improvements" section reads as the record of what was done. Follow-ups that were out of scope:

- **Two dropzone implementations.** The picture gallery uses the Dropzone.js library with
  ActiveStorage direct uploads into hidden fields the form saves later; the receipts one is a
  small Stimulus controller that posts to the server and streams the gallery back. Both accept a
  drop in Chromium (verified with synthetic drag events on the zone and on a child element), so
  the reported "drag does nothing, click works" could not be reproduced. Unifying them means
  picking one upload model, which is its own piece of work.
- **PDF receipt thumbnails** render as a broken image where the server has no PDF previewer; the
  viewer already falls back to a document icon once the image errors, so this is cosmetic.


Visual review of every admin form touched since July, against three older forms as the house-style
baseline (News, Venues, Users). Every page was captured on the real dev server at 1280 wide in a
tall viewport (the admin layout scrolls inside `<main>`, so full-page stitching cannot reach below
the fold), and the six most complex ones again at 390 wide. The measurement sweep ran on every
cell; the only leads it raised are the same two on every page (sidebar links under 44px, and the
`sr-only` "Toggle sidebar" span), so they are layout chrome, not form defects.

Evidence: `tmp/screenshots/form-review/<route>_{1280,1280-tall,390}.png` (gitignored).

## The root cause: two form systems

The older admin forms all go through one path: `simple_horizontal_form_for` + `shared/pages/_form`.
That gives every form the same shape: a card, a fixed label column at x=313 with inputs from x=545
to the card edge, hints in small grey under the input, required stars, and the buttons in a grey
card footer via `shared/form/_form_actions`.

Everything built for the reimbursements finance side and the climate monitor hand-rolls `form_with`
instead, with labels stacked above inputs, an inline class string on every control, per-field
widths picked by hand (`w-40`, `w-64`, `w-72`, `max-w-md`, `max-w-xl`, `w-full`), and the submit
button sitting in the card body. Two producer-facing pages (expense new/edit, payment details) and
the actuals conversion use the house path; nothing else in those namespaces does.

| Convention | Forms |
|---|---|
| simple_form horizontal + `shared/pages/form` | News, Venues, Users, Carousel, Opportunities, Shows, Expenses new/edit, Payment details, Actuals → expense |
| simple_form vertical, no card footer | Climate sensors new/edit |
| hand-rolled `form_with` + inline classes | Finance expense edit, Budgets new/edit, Settings new/edit, Financial years new/edit, Budget import, Budget updates, Build batch, Reconcile, Climate import |

Measured spread of the hand-rolled vocabulary:

| Thing | Count |
|---|---|
| Copies of `border border-gray-300 rounded px-2 py-1 text-sm` | 73, across 19 views |
| Distinct back-link styles (`← All …`) | 5 |
| Unstyled native file inputs ("Choose File No file chosen" as bare text) | 4 |
| Submit buttons in the card body rather than the footer | 12 forms |

The five back-link variants: `text-sm text-primary underline`, `text-primary underline` (no
`text-sm`), `text-sm text-blue-700 hover:underline` (no underline at rest), `text-info underline`,
`text-gray-600 underline`.

## Defects, most severe first

**D1 (should-fix) Budget "Type" select paints its chevron over the text.**
Expected: the option text fully readable. Observed: at 1280 the select is 66px wide (x=801–867)
and the native chevron sits on the "se" of "Expense". Reproduction: `/admin/reimbursements/budgets/4/edit`
and `/budgets/new`, 1280×900. Evidence: `admin_reimbursements_budgets_4_edit_1280.png`. Cause
(hypothesis): the only control in that row with no width class, so it shrinks to content and the
`px-2` leaves no room for the arrow (`budgets/edit.html.erb:21`, `budgets/new.html.erb:29`).
Acceptance: "Expense" and "Income" both readable with the chevron clear of the text.

**D2 (should-fix) Finance expense edit is a different form from every other form.**
Small `text-sm` controls in a two-column grid, stacked labels, the Save button inside the body as a
small outlined button, and the receipt panel with its own unstyled file input and an "Attach"
button. It sits one click from the producer's edit page for the same record, which is a
full-width horizontal form with footer buttons. Evidence: `admin_reimbursements_expense_edits_10_edit_1280.png`
against `admin_reimbursements_expenses_9_edit_1280.png`. Within it:
- the three payee-override fields are unequal heights because "Account no. override" wraps to two
  lines and pushes its input 20px below its neighbours (x=713, y=678 vs y=658);
- the receipt is listed twice, once as the thumbnail and once as "receipt.pdf [Remove]";
- the "Choose Files No file chosen" control is browser-default text next to a styled button.

**D3 (should-fix) Settings: the role picker draws a box inside a box.**
Observed: a 288px bordered box (x=305–593) with a narrower Tom Select control inside it (x=315–583),
so the field has a double border and does not line up with the mailbox inputs above it.
Reproduction: `/admin/reimbursements/settings/fringe/edit` and `/settings/new`, 1280×900. Evidence:
`admin_reimbursements_settings_fringe_edit_1280.png`. Cause (hypothesis): the `border … w-72`
classes are on the underlying `<select class="simple-select2">`, and `select_controller.js` wraps it
in Tom Select's own bordered `.ts-wrapper`, which inherits the width (`settings/edit.html.erb:19`,
`settings/new.html.erb:49`). Acceptance: one border, same width and left edge as the inputs above.

**D4 (should-fix) Producer expense form: two inset boxes break the label column.**
The receipt box (new only) and the "Pay someone else" box put their own `p-3` padding around
horizontal-form rows, so their labels start at x=330 and inputs at x=553 while the rows outside
start at x=313 / x=545. The reference counter ("18 of 18 characters left") is a separate `<p>`
outside the row, so it renders at the card padding (x=305) in body-size dark text rather than
under the field as a hint. Reproduction: `/admin/reimbursements/expenses/new`, 1280. Evidence:
`admin_reimbursements_expenses_new_1280.png` (compare `admin_users_1_edit_1280.png`). Cause:
`expenses/_form.html.erb:52`, `:130`, `:143`. Acceptance: every label at x=313 and every input at
x=545 down the whole form; the counter sits under the reference input in hint styling.

**D5 (should-fix) Show edit: the running-time row and the nested sections collapse the grid.**
"Running time (minutes)" / "Doors open (minutes before)" / "Age guidance" share one row with the
labels squeezed into 60–80px columns, so they wrap to three lines and their inputs sit at three
unrelated x positions (x=378, 657, 937) with hints of different heights. "Performances" and
"Ticket prices" are headings with an "+ Add" button, followed directly by the next ordinary field
("Venue", "Booking fee") with 12px of space, so the section has no visible end and the button
looks like it belongs to the field below. Reproduction: `/admin/shows/halfbaked/edit`, 1280.
Evidence: `admin_shows_halfbaked_edit_1280-tall.png`. Cause (hypothesis): `admin/events/_basic_form.erb`
and `shared/form/sections/_nested_fields.erb` (the Gallery section at the bottom, which is in a
collapsible card, reads fine by contrast).

**D6 (nit) Unstyled file inputs on the two import pages and the finance receipt attach.**
Budget import and Climate import render the native "Choose File No file chosen" as plain text under
a bold label, while the same control on News / Carousel / Expenses is a grey "Choose File" button.
Evidence: `admin_reimbursements_financial_years_2027-28_budget_import_1280.png`,
`admin_climate_import_new_1280.png`. Cause: `file_field_tag … class: "text-sm"` with no button styling
(`budget_imports/show.html.erb:59`, `climate/imports/new.html.erb:46`, `expense_edits/edit.html.erb:185`,
`review/_expense_card.html.erb:294`).

**D7 (nit) Section intros butt against the first field.**
Climate sensor new/edit: the intro paragraph has no bottom margin, so the "Name" label sits 13px
under it where every other gap on the form is 24px. Opportunities edit: the "+ Add Role" button is
21px above the "Attribution (optional)" heading, closer than the fields are to each other.
Evidence: `admin_climate_sensors_1_edit_1280.png`, `admin_opportunities_16087876_edit_1280-tall.png`.

**D8 (nit) Expense edit repeats itself and orphans the delete.**
The page opens with "This claim is a draft. Only you can see it. Finish it and submit it below."
and the card footer says "This claim is a draft. Only you can see it. Submit expense sends it…".
"Delete draft" then sits below the card, separated by a bare top border, with its own hint. Evidence:
`admin_reimbursements_expenses_9_edit_1280-tall.png`.

**D9 (nit) Back links and settings warnings are styled five ways.**
See the table above. The Settings edit page also puts a red `text-xs` warning ("This role has no
members") and a grey `text-xs` hint under the same field, then a `-mt-2` hack to pull a second
paragraph up. Evidence: `admin_reimbursements_settings_fringe_edit_1280.png`.

Not counted: the PDF receipt thumbnail renders as a broken image on both expense edit pages. That
is the dev machine lacking a PDF previewer (the `<img>` requests a preview variant), not the form.
Worth a fallback icon regardless, since a producer on a phone sees the same broken-image glyph if
a preview ever fails.

## Improvements, per form

The cheapest route to "unified" is to stop maintaining the second system. simple_form already does
everything the hand-rolled forms do, including forms without a model: `simple_form_for :cost_centre,
url: …` takes a symbol scope, and `f.input :name, as: :string` works against `params`. The
horizontal wrappers (`tailwind_horizontal_*`) are what the baseline forms use; the vertical ones
(`vertical_form`, the default) are what the sensor form uses and are the natural fit for the
short finance forms.

### Cross-cutting (do these first, they close most of the list)

1. **One back link.** A `shared/_back_link` partial (or a `back_link(text, path)` helper) with a
   single class string. Replace all 16 call sites. Closes D9's first half.
2. **One file input.** Route every `file_field_tag` through simple_form's `:file` input (the
   `vertical_file` / `tailwind_horizontal_file` wrappers already style it) or the existing
   `shared/form/_file_field` partial. Closes D6.
3. **Buttons in the footer.** Every form that renders inside a `CardComponent` should use
   `shared/pages/form` (card + footer) or at least the card's `footer` slot, so "Save" always sits
   in the grey band, always with "Cancel" beside it. Today Cancel exists on 6 of the 20 forms.
4. **Delete the inline class string.** Once the finance forms use simple_form the 73 copies go.
   Where a bare `text_field_tag` genuinely stays (search bars, the per-row forms on the People and
   Review pages), give it a helper (`input_classes`) rather than the literal.
5. **Tom Select and borders.** Whatever the answer to D3, apply it in one place: the `.simple-select2`
   selector should carry width only; the border belongs to the widget.

### Producer expense form (`expenses/_form`, new + edit)

Closest to the house style already, so keep the horizontal layout and fix the four things that
break it:
- Drop the bordered inset around the receipt input on `new`. Make the explanatory paragraph the
  input's `hint:` (it is long, but hints already wrap) and keep only the yellow "please re-attach"
  notice as a box, since that one is a warning.
- Turn "Pay someone else" into a section rather than a box: a heading row spanning the form (the
  way "User Details" does on the Users form), the "(optional)" / "(required for an invoice)" /
  "In use" badge on that heading, the three fields as ordinary rows underneath. The heading can
  still colour when overrides are in use. This puts the labels back at x=313.
- Render the reference counter as the hint of `payment_reference` (the counter `<span>` inside the
  hint text) so it sits in the hint column in hint styling.
- On `edit`, remove the duplicate sentence from the top banner (keep the banner for the Pending
  case, which says something the footer does not) and move "Delete draft" into the footer as a
  right-aligned danger button with its hint as a `title`, or as the last item of the footer text.
- Receipt thumbnail: fall back to a document icon when the preview variant is missing.

### Finance expense edit (`expense_edits/edit`)

Rebuild the left column as `simple_form_for :expense, url:` inside `shared/pages/form`:
- Full-width horizontal rows for Type, Amount / Amount excl. VAT (two inputs in one row is fine,
  use a `flex gap-4` inside the input column), Description, Payment reference, Budget, Nominal code
  override (with "Effective nominal" as its hint).
- "Payee overrides" as a section heading row, then three ordinary rows. That removes the wrapping
  label and the uneven heights outright, and matches how the producer form will read.
- Save + Cancel (back to the expenses index) in the footer.
- Replace the receipt panel's list + native file input + Attach with the `receipts-upload` dropzone
  and `receipts_gallery` partial the producer edit page already has. The finance routes exist
  (`expense_edit_receipts`), so it is a matter of pointing the controller's `url` value at them.
  The thumbnail's "×" then removes; the duplicate filename list goes.
- Keep the header meta strip and the attention alerts; they are the reason this page exists.

### Budgets new/edit (`budgets/new`, `budgets/edit`)

- simple_form vertical: Name / Nominal code / Type / Initial budget as a 4-column grid row with
  equal widths (`grid sm:grid-cols-4 gap-4`), which also fixes D1 because the select gets a real
  width. Cost centre joins that row when there is more than one.
- Owners as `f.input :owner_ids, as: :check_boxes, collection: @people` in the
  `vertical_collection` wrapper. Lose the bordered scroll box unless the list is long; if it is,
  `max-h-48 overflow-y-auto` on the wrapper is enough without a border.
- Notes full width. Save + Cancel in the footer.
- The forecast add row at the bottom of the "Budget forecasts" card is an inline table-footer
  form and can stay as it is; give it the shared input helper.

### Settings new/edit (`settings/new`, `settings/edit`)

- Same simple_form vertical treatment. Two-up rows for the mailboxes and for EUSA recipient /
  EUSA contact name; everything else full width. That removes the `w-72` vs `max-w-xl` vs
  `-mt-2` juggling.
- Role picker: width class only on the select (D3).
- "This role has no members" as an `AlertComponent.new(type: :warning)` under the field (the same
  component the page already uses for the Microsoft-access section), not red `text-xs`.
- Move the yellow "Microsoft access for this cost centre" collapsible out of the middle of the
  fields. It is documentation for IT, not a field; it belongs after the Save button or inside the
  "Check Microsoft access" card, where the "Run access check" button it tells you to press lives.
- Save + Cancel in the footer. The nightly run-day checkboxes are fine as an inline collection.

### Financial years new/edit (`financial_years/_form`)

- simple_form vertical; Starts on / Ends on as a two-up row with the shared hint as the row's
  hint rather than a `-mt-2` paragraph. Save + Cancel in the footer. The "Advanced" collapsible is
  good and should stay.

### Budget import and Climate import (`budget_imports/show`, `climate/imports/new`)

These are the same screen: pick a target, paste or upload. Extract one `shared/form/_paste_or_upload`
partial (textarea with monospace placeholder + styled file input + "…or" divider) and use it on
both, plus Reconcile, which is the same shape again. Climate import also uses `form-control`, the
Bootstrap-compat class, on its select and textarea: a third vocabulary that goes with this change.
Buttons in the footer.

### Budget updates new, Build batch, Reconcile

Already tidy; only the cross-cutting items apply (back link, footer buttons, inline classes).
On Build batch, "Draft sent from" is a read-only value dressed as a field; render it as
`f.input … disabled: true` or as a plain line in the intro so it stops looking editable.

### Climate sensors new/edit

`mb-4` on the intro paragraph (D7). Move the Save/Cancel into the card footer. Otherwise this is
the model for the vertical style.

### Show edit (`events/_basic_form`)

- Running time / Doors open / Age guidance: either three ordinary horizontal rows, or one row whose
  input column holds three stacked-label inputs of equal width (`grid grid-cols-3 gap-4`). The
  current version tries to fit three label+input pairs into the label column's width.
- "Performances" and "Ticket prices": wrap each in the same collapsible card the Gallery uses, or
  at minimum put the "+ Add" button *after* the rows it adds and give the section a bottom margin
  and a divider before the next plain field. Right now the heading, paragraph and button read as a
  preamble to "Venue".
- "You have not set any tags" is a full-width danger alert between two fields; it is advisory, so
  it should be the `hint:` of the Event Tags input, or a warning-coloured hint, not a red box.

### Opportunities edit, Carousel, Actuals → expense, Payment details

Nothing beyond the cross-cutting items. Opportunities: `mb-4` under the "+ Add Role" button (D7).

## Suggested order

1. Cross-cutting 1–3 (back link, file input, footer buttons) in one branch. Mechanical, low risk,
   and they change the look of every finance page at once.
2. Finance expense edit (D2) and producer expense form (D4, D8) together, since the goal is that
   the two edit pages for one claim read as siblings.
3. Budgets + Settings + Financial years (D1, D3, D9) as one "finance forms onto simple_form" branch.
4. Show edit (D5), which is the one older form with a real layout problem.
5. Imports partial and the sensor / opportunities nits.

Each step is screenshot-verifiable against the captures in `tmp/screenshots/form-review/`.

## Coverage ledger

Theme: the app has no dark mode (no `dark:` variants anywhere), so one theme. DPR 1 throughout.

| Cell | Route | Viewport | State | Evidence | Defects |
|---|---|---|---|---|---|
| 1 | /admin/reimbursements/expenses/new | 1280×900, 1280×3000, 390×4200 | empty, 1 budget | `…expenses_new_*` | D4 |
| 2 | /admin/reimbursements/expenses/9/edit | 1280×900, 1280×3000 | Draft, 1 PDF receipt | `…expenses_9_edit_*` | D4, D8 |
| 3 | /admin/reimbursements/expense_edits/10/edit | 1280×900, 1280×5200, 390×4200 | Pending, 1 receipt | `…expense_edits_10_edit_*` | D2, D6 |
| 4 | /admin/reimbursements/settings/fringe/edit | 1280×900, 1280×5200, 390×4200 | role with no members | `…settings_fringe_edit_*` | D3, D9 |
| 5 | /admin/reimbursements/settings/new | 1280×900, 1280×3000 | empty | `…settings_new_*` | D3, D9 |
| 6 | /admin/reimbursements/budgets/4/edit | 1280×900, 1280×5200, 390×4200 | populated, no forecasts | `…budgets_4_edit_*` | D1 |
| 7 | /admin/reimbursements/budgets/new | 1280×900, 1280×3000 | empty | `…budgets_new_*` | D1 |
| 8 | /admin/reimbursements/batches/new | 1280×900, 1280×3000, 390×4200 | 1 approved expense | `…batches_new_*` | — (sweep clean) |
| 9 | /admin/reimbursements/financial_years/2027-28/edit | 1280×900, 1280×3000 | draft year | `…financial_years_2027-28_edit_*` | D9 |
| 10 | /admin/reimbursements/financial_years/new | 1280×900, 1280×3000 | empty | `…financial_years_new_*` | D9 |
| 11 | /admin/reimbursements/financial_years/2027-28/budget_import | 1280×900, 1280×3000, 390×4200 | empty | `…budget_import_*` | D6, D9 |
| 12 | /admin/reimbursements/budget_updates/new | 1280×900, 1280×3000 | 2 budgets | `…budget_updates_new_*` | — (sweep clean) |
| 13 | /admin/reimbursements/payment_details/edit | 1280×900 | populated | `…payment_details_edit_1280` | — (sweep clean) |
| 14 | /admin/reimbursements/actuals/9/new_expense | 1280×900, 1280×3000 | unlinked debit | `…actuals_9_new_expense_*` | — (sweep clean) |
| 15 | /admin/reimbursements/reconciliation | 1280×900, 1280×3000 | step 1 | `…reconciliation_*` | — |
| 16 | /admin/climate/import/new | 1280×900, 1280×3000 | 1 sensor | `…climate_import_new_*` | D6 |
| 17 | /admin/climate/sensors/new | 1280×900, 1280×3000 | empty | `…climate_sensors_new_*` | D7 |
| 18 | /admin/climate/sensors/1/edit | 1280×900, 1280×3000 | outdoor source | `…climate_sensors_1_edit_*` | D7 |
| 19 | /admin/shows/halfbaked/edit | 1280×900, 1280×3000 | populated, no occurrences | `admin_shows_*` | D5 |
| 20 | /admin/opportunities/16087876/edit | 1280×900, 1280×3000 | populated, no roles | `…opportunities_*` | D7 |
| 21 | /admin/carousel_items/1/edit | 1280×900, 1280×3000 | populated | `…carousel_items_*` | — |
| 22 | /admin/news/new (baseline) | 1280×900, 1280×3000 | empty | `admin_news_new_*` | — |
| 23 | /admin/venues/new (baseline) | 1280×900, 1280×3000 | empty | `admin_venues_new_*` | — |
| 24 | /admin/users/1/edit (baseline) | 1280×900, 1280×3000 | populated | `admin_users_1_edit_*` | — |

Unreviewed, with reason:
- Error states (a 422 re-render with field errors) on every form: not captured. The producer
  expense form's re-attach notice and the `:base` error list in `shared/pages/_form` are the two
  error surfaces most likely to differ; worth a pass once the layout work lands.
- Budget import and Reconcile *preview* steps: need a pasted sheet; not forms in the sense reviewed
  here.
- Review queue card forms (`review/_expense_card`): per-row inline forms, out of scope, but they
  carry 8 copies of the inline class string and inherit whatever helper replaces it.
- The `app/views/reimbursements/…` paths in the git log are deletions (the portal moved under
  `/admin` in b675cb25); there is nothing there to capture.
