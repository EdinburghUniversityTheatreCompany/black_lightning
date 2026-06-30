# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

## Image processing follow-ups

- **`lib/RQRCode/renderers.rb` MiniMagick SVG path looks dead.** It calls
  `MiniMagick::Image.read(svg)`, which needs ImageMagick — installed neither locally nor in the
  Dockerfile (only `libvips`). The live mailer (`app/mailers/membership_mailer.rb`) uses the
  chunky_png `RQRCode::Renderers::PNG` renderer instead, so the MiniMagick path appears unused.
  If confirmed dead, remove the custom renderer (and possibly the `mini_magick` gem, once the
  representations controller no longer references `MiniMagick::Error`); otherwise add ImageMagick
  to the Docker image so it actually works.

## dev-env standard (v17) — gate ratchet status

The dev-env-setup (replacing overcommit with hk, 2026-06) introduced strict gates that surfaced
pre-existing debt overcommit never checked. Ratchet status (the `ratchet-gates` work, 2026-06):

- **herb (ERB lint) — DONE, now GATING.** The backlog was driven from ~190 errors to **0 errors /
  0 warnings** and `herb-lint` no longer carries `|| true` in `hk.pkl` / `ci.yml`. Two over-broad
  rules are intentionally disabled in `.herb.yml` with rationale (`erb-no-instance-variables-in-partials`
  and `actionview-no-silent-helper` — the latter's 37 flags were all the codebase's
  `fields = {...}` / `quick_actions << link_to` view-data pattern, not swallowed output). 8 reviewed-safe
  `raw`/`html_safe` uses carry same-line `herb:disable`. `herb-analyze` stays advisory ONLY because the
  two HTML-email fragment partials (`shared/mail/_header|_footer`) can't be parsed standalone (excluded
  from herb-lint; `herb analyze` has no exclude flag). Real fixes included two `<%= %>`-in-attribute
  SecurityErrors (sidebar_component, _merge_modal radios → `tag.*` helpers) and several parse bugs.
- **jscpd duplication — DONE, now GATING at threshold 0.** Driven from 32 clones / 1.0% to **0 / 0.0%**.
  `swalCustomTheme.scss` (CSS theme variants) and `bin/**` (generated binstubs) are excluded in
  `.jscpd.json`; the real code clones were refactored (shared `import_parsing` concern, `build_ical_event`,
  simple_form wrapper procs, `db/seeds/helpers.rb`, and `test/support/` helpers).
- **database_consistency — PARTIALLY ratcheted, still ADVISORY (`|| true`).** Reduced from ~382 findings:
  - **Done:** all 144 `LengthConstraintChecker` findings fixed with model `length: { maximum: N }`
    validations; the legacy integer-PK checkers (`PrimaryKeyTypeChecker` 31 + `ForeignKeyTypeChecker` 17)
    scoped out in `.database_consistency.yml` (documented — see CLAUDE.md › Database).
  - **Deferred (the remaining ~170 findings — a real follow-up SCHEMA-MIGRATION project):**
    `ColumnPresenceChecker` (101 → add NOT NULL), `ForeignKeyChecker` (22 → add FKs),
    `MissingUniqueIndexChecker` (21), `ThreeStateBooleanChecker` (15 → NOT NULL boolean + default),
    and the remaining index checkers. These require **data-aware backfill migrations on the legacy
    production DB** (columns may contain nulls / duplicates), which `strong_migrations` correctly
    blocks as unsafe and which need a production data audit. Do them as guarded multi-step migrations
    (backfill → add constraint) once the data is verified; then drop the `|| true` to gate. Note the
    legacy integer-PK FK columns also can't take a `t.references ... type: :integer` FK trivially.

Note (RESOLVED): the standard's hk `test` step would run the **full `bin/rails test` suite on every
commit** staging a `.rb` file (~minutes on this repo). It has been moved to the `check` hook only
(run by `hk run check` + mirrored by CI's `test` job), so **pre-commit does not run the suite**.
pre-commit still runs the fast linters/audits (rubocop, herb, jscpd, brakeman, debride, flay,
database_consistency, gitleaks) on staged files — if those also prove too slow, move the heavier
audits (brakeman/jscpd/debride/flay) to `check` the same way.
