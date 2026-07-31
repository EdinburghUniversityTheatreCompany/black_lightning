# Deferred dependency upgrades

Upgrades that could **not** be applied during a dependency sweep, with the reason and the manual
steps needed to land them later. Last reviewed: **2026-07-31**.

Every Ruby entry below is blocked by a constraint outside this repo — re-check with
`bundle outdated` / `pnpm outdated`; anything still listed here is expected to appear.

## ~~`annotate` 2.6.5 → 3.x~~ — DONE: swapped to `annotaterb`

**Resolved** in the annotaterb migration commit. The unmaintained `annotate` gem
(ctran/annotate_models) capped at `activerecord < 8.0` and its 2.6.5 binary was already broken
on Ruby 4.0 (`File.exists?`), so it was replaced with **`annotaterb` 4.22.0** (drwl/annotaterb),
the maintained drop-in that supports Rails 8.x / Ruby 4.x. The legacy malformed RDoc schema
blocks were stripped and regenerated in the standard plain format (RDoc format is non-idempotent
in annotaterb). See the **Schema annotations** note in `CLAUDE.md` for the resulting setup.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby) — blocked by an upstream constraint

**Why deferred:** `diff-lcs` is a transitive dependency. `solargraph` (0.60.2) constrains it to
`~> 1.4`, so 2.0.0 cannot be resolved until solargraph relaxes that bound. No action needed in
this repo; it will move once solargraph ships a release that allows `diff-lcs` 2.x.

## `rdoc` 7.2.0 → 8.0.0 (Ruby) — blocked by the same upstream constraint

**Why deferred:** the same `solargraph` 0.60.2 pins `rdoc (~> 7.0)`. We declare `rdoc` directly
(`group :development, :test`), but bundler cannot resolve 8.x while solargraph is in the bundle —
`bundle update rdoc` reports "attempted to update rdoc but its version stayed the same". When
solargraph widens the bound, note that **RDoc 8 drops the Ripper-based parser for Prism** and
removes deprecated CLI options/directives; nothing here drives rdoc programmatically, so the
bump should be inert for us.

## `highline` 3.0.1 → 3.1.2 (Ruby) — blocked by an upstream constraint

**Why deferred:** transitive via `commander` 5.0.0, which pins `highline (~> 3.0.0)` — a
pessimistic constraint at the patch level, so even 3.1.x is out. Moves when commander does.

## `rack-proxy` 0.8.3 → 1.0.1 (Ruby) — blocked by an upstream constraint

**Why deferred:** transitive via `vite_ruby` 3.10.2, which pins
`rack-proxy (~> 0.6, >= 0.6.1)`; `~> 0.6` disallows 1.x. Moves when vite_ruby widens it.

## `dropzone` 5.9.3 → 6.0.0-beta.2 (JS) — prerelease only

**Why deferred:** The only newer release is `6.0.0-beta.2`, a prerelease. Held at the latest
stable `5.9.3`. Revisit once a stable `6.0.0` ships (v6 is a rewrite — read its migration notes
before bumping, as the API/DOM hooks change).

## Held back by the supply-chain cooldown — not deferred, just young

pnpm applies a 4-day `minimumReleaseAge`, so a release newer than that is skipped **by design**
and lands on the next sweep. At the 2026-07-31 sweep that was `vite` 8.2.0 (we took 8.1.5).
Nothing to do — do not disable the cooldown to grab it.
