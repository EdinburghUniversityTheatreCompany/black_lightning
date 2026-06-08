# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

## Opportunities feature follow-ups

- **Public submission can create unlimited `Company` records.** A logged-out submitter who
  passes reCAPTCHA (or any logged-in member, who skips it) creates a `Company` via the
  `company_name` field on every submission. Moderation only gates the `Opportunity`, not the
  `Company`, so the companies table (used for the public filter dropdown) can be polluted.
  Consider creating the company only on approval, deduping/merging in review, or rate-limiting.
  (`app/controllers/get_involved_controller.rb#find_or_create_company`)

- **Honeypot uses `display:none`.** The public submission honeypot (`website_url`) is hidden with
  Tailwind `hidden` (display:none), which modern bots often skip. An off-screen technique
  (absolute + `left:-9999px`) catches more while staying invisible. reCAPTCHA is the primary
  defence, so this is a minor hardening. (`app/views/get_involved/new.html.erb`)

- **Inert sortable handle on the public role form.** `admin/opportunities/_opportunity_role_fields`
  renders a drag handle (⠿) and a `data-display-order` field for the admin's `sortable` Stimulus
  controller. The public submission form reuses this partial without `sortable: true`, so the
  handle is shown but does nothing. Making the handle conditional would require threading a flag
  through the shared `shared/form/sections/_nested_fields.erb` (a KEEP partial) and its strict-locals
  item partials, so it was left as-is.

- **Description editor inconsistency.** The public opportunity form uses a plain `<textarea>` for the
  (Markdown) description, while the public complaints form uses `shared/form/_md_editor`. Aligning
  them would give external submitters a Markdown editor — at the cost of the MdEditor's
  Playwright-untestability. Deliberate divergence for now.

- **Internal-first ordering lives in three places:** `Company.internal_first`, the `Opportunity.active`
  scope's raw SQL, and the public listing's Ransack `company_internal desc` sort. Consider
  centralising the tie-break rule.

- **reCAPTCHA fails closed silently if production keys are missing.** With no credentials in
  production, `verify_recaptcha` rejects every logged-out submission with only a generic flash.
  A boot-time check or log would surface the misconfiguration. (`config/initializers/recaptcha.rb`)

## Pre-existing (not introduced here)

- **Several opportunity fixtures reference `creator: admin`** while the `admin` user fixture has an
  explicit `id: 1`, so their `.creator` association loads as `nil` (see the CLAUDE.md gotcha). Nothing
  currently relies on it, but switching them to `creator_id: 1` would make the fixtures correct.
  (`test/fixtures/opportunities.yml`)
