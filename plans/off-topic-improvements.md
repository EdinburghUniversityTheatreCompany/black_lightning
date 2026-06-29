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

## dev-env standard (v17) — gate baselines to ratchet down

The dev-env-setup (replacing overcommit with hk, 2026-06) introduced strict gates that surface
pre-existing debt overcommit never checked. They were set to a **green baseline** so the setup is
usable today; tighten each over time and remove the baseline marker when clean:

- **herb (ERB lint + analyze) — currently ADVISORY (`|| true`) in `hk.pkl` + `ci.yml`.**
  `herb lint app/` reports ~190 errors across ~91 files; `herb analyze app/` reports 8 files,
  **including 2 genuine `<%= %>`-in-attribute-position SecurityErrors worth fixing first**:
  `app/components/admin/sidebar_component.html.erb:60` and
  `app/views/admin/users/_merge_modal.html.erb:72`. Work the backlog down (`herb lint app/ --fix`
  handles the autocorrectable ones), then drop the `|| true` to re-gate. Noisiest rules:
  `erb-no-instance-variables-in-partials` (165), `actionview-no-silent-helper` (75),
  `erb-no-duplicate-branch-elements` (57) — can be disabled per-rule in `.herb.yml` if not wanted.
- **jscpd duplication — threshold baselined at 1.5% in `.jscpd.json`** (current ~1.0%, 32 clones).
  Blocks NEW duplication above the baseline. Refactor clones and ratchet toward the standard's `0`.
  `npx skills add https://github.com/kucherenko/jscpd --skill dry-refactoring` can auto-fix clones.
- **database_consistency — currently ADVISORY (`|| true`) in `hk.pkl` + `ci.yml`.** ~380 findings,
  mostly the documented legacy integer-PK schema (`PrimaryKeyTypeChecker` 31, `LengthConstraintChecker`
  144, `ColumnPresenceChecker` 101, missing FKs 22). Address via `strong_migrations`-guarded
  migrations and/or a `.database_consistency.yml` to scope out intentional legacy choices, then
  drop the `|| true`.

Note (RESOLVED): the standard's hk `test` step would run the **full `bin/rails test` suite on every
commit** staging a `.rb` file (~minutes on this repo). It has been moved to the `check` hook only
(run by `hk run check` + mirrored by CI's `test` job), so **pre-commit does not run the suite**.
pre-commit still runs the fast linters/audits (rubocop, herb, jscpd, brakeman, debride, flay,
database_consistency, gitleaks) on staged files — if those also prove too slow, move the heavier
audits (brakeman/jscpd/debride/flay) to `check` the same way.
