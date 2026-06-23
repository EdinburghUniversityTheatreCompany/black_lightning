# Deferred dependency upgrades

Upgrades that could **not** be applied during the dependency sweep on 2026-06-23, with the
reason and the manual steps needed to land them later.

## `annotate` 2.6.5 → 3.x (Ruby) — needs a gem swap to `annotaterb`

**Why deferred:** The `annotate` gem (ctran/annotate_models) is unmaintained and incompatible
with this app:

- `annotate` 3.2.0 (the latest) requires `activerecord >= 3.2, < 8.0`. This app is on Rails
  **8.1**, so bundler refuses the bump and holds it at 2.6.5.
- The installed `annotate` 2.6.5 binary is **already broken** on Ruby 4.0: its `bin/annotate`
  calls `File.exists?`, removed in Ruby 3.2 (`undefined method 'exists?' for class File`). So the
  command does not run today — this is a pre-existing breakage, not a regression from this sweep.

**Recommended fix:** migrate to **`annotaterb`** (drwl/annotaterb), the maintained drop-in
successor that supports Rails 8.x and Ruby 4.x. Manual steps:

1. In the `Gemfile`, replace `gem "annotate"` with `gem "annotate_rb"` (in the same
   `:development, :test` group).
2. `bundle install`.
3. `bundle exec annotaterb install` to generate `.annotaterb.yml` and the
   `lib/tasks/auto_annotate_models.rake` hook.
4. Note the v3 behaviour change carried over from `annotate`: models are **not** annotated unless
   `models: true` (config) / `--models` (CLI) is set — set `models: true` in `.annotaterb.yml`.
5. `bundle exec annotaterb models` to regenerate the `== Schema Information` blocks, review the
   diff, and commit.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby) — blocked by an upstream constraint

**Why deferred:** `diff-lcs` is a transitive dependency. `solargraph` constrains it to
`~> 1.4`, so 2.0.0 cannot be resolved until solargraph relaxes that bound. No action needed in
this repo; it will move once solargraph ships a release that allows `diff-lcs` 2.x.

## `dropzone` 5.9.3 → 6.0.0-beta.2 (JS) — prerelease only

**Why deferred:** The only newer release is `6.0.0-beta.2`, a prerelease. Held at the latest
stable `5.9.3`. Revisit once a stable `6.0.0` ships (v6 is a rewrite — read its migration notes
before bumping, as the API/DOM hooks change).
