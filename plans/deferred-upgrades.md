# Deferred dependency upgrades

Upgrades that could **not** be applied during the dependency sweep on 2026-06-23, with the
reason and the manual steps needed to land them later.

## ~~`annotate` 2.6.5 → 3.x~~ — DONE: swapped to `annotaterb`

**Resolved** in the annotaterb migration commit. The unmaintained `annotate` gem
(ctran/annotate_models) capped at `activerecord < 8.0` and its 2.6.5 binary was already broken
on Ruby 4.0 (`File.exists?`), so it was replaced with **`annotaterb` 4.22.0** (drwl/annotaterb),
the maintained drop-in that supports Rails 8.x / Ruby 4.x. The legacy malformed RDoc schema
blocks were stripped and regenerated in the standard plain format (RDoc format is non-idempotent
in annotaterb). See the **Schema annotations** note in `CLAUDE.md` for the resulting setup.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby) — blocked by an upstream constraint

**Why deferred:** `diff-lcs` is a transitive dependency. `solargraph` constrains it to
`~> 1.4`, so 2.0.0 cannot be resolved until solargraph relaxes that bound. No action needed in
this repo; it will move once solargraph ships a release that allows `diff-lcs` 2.x.

## `dropzone` 5.9.3 → 6.0.0-beta.2 (JS) — prerelease only

**Why deferred:** The only newer release is `6.0.0-beta.2`, a prerelease. Held at the latest
stable `5.9.3`. Revisit once a stable `6.0.0` ships (v6 is a rewrite — read its migration notes
before bumping, as the API/DOM hooks change).
