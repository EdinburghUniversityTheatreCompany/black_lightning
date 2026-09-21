# Deferred dependency upgrades

Upgrades that could **not** be applied during a dependency sweep, with the reason and the manual
steps needed to land them later. Last reviewed: **2026-09-21**.

Every Ruby entry below is blocked by a constraint outside this repo — re-check with
`bundle outdated` / `pnpm outdated`; anything still listed here is expected to appear.

## ~~`annotate` 2.6.5 → 3.x~~ — DONE: swapped to `annotaterb`

**Resolved** in the annotaterb migration commit. The unmaintained `annotate` gem
(ctran/annotate_models) capped at `activerecord < 8.0` and its 2.6.5 binary was already broken
on Ruby 4.0 (`File.exists?`), so it was replaced with **`annotaterb`** (drwl/annotaterb), the
maintained drop-in that supports Rails 8.x / Ruby 4.x. The legacy malformed RDoc schema blocks
were stripped and regenerated in the standard plain format (RDoc format is non-idempotent in
annotaterb). See the **Schema annotations** note in `CLAUDE.md` for the resulting setup.

## ~~`rack-proxy` 0.8.3 → 1.x~~ — DONE at the 2026-09-21 sweep

**Resolved.** It was transitive via `vite_ruby` 3.10.2, whose `~> 0.6` disallowed 1.x. vite_ruby
3.11.0 relaxed that to `rack-proxy (>= 0.6.1)`, so the sweep took it straight to **2.0.1**. It
backs `ViteRuby::DevServerProxy`, which only sits in the middleware stack while a Vite dev server
is running; both suites are green with it.

## ~~`dropzone` 5.9.3 → 6.x~~ — DONE at the 2026-09-21 sweep

**Resolved.** The 6.0.0 line went stable on 2026-09-05, so the prerelease objection is gone and
**6.3.4** is in. The one API change that touched us was `Dropzone.autoDiscover`, removed in 6
(you call `Dropzone.discover()` now, which we don't need — `dropzone_controller.js` constructs
its own instance), so that line was deleted. `Dropzone.extend` and `Dropzone.version` also went,
and neither was used. CSS is still at `dropzone/dist/dropzone.css`. No system test covers the
dropzone, so it was verified by hand in a browser: file dropped, `POST
/rails/active_storage/direct_uploads` 200 → blob `PUT` 204, no console errors. The bundle also
fell from 114 kB to 38 kB (6.x stopped transpiling for browsers it had already dropped).

## `json` 2.21.2 → 3.x (Ruby) — blocked by Rails, and now constrained in the Gemfile

**Why deferred:** json 3 made `JSON.parse`'s options **keyword-only**
(`parse(source, on_load:, object_class:, array_class:, **options)`), while Rails 8.1.3.1's
`ActiveSupport::JSON.decode` still passes them positionally (`::JSON.parse(json, options)` at
`active_support/json/decoding.rb:25`). So **every** serialized / JSON column raises
`ArgumentError: wrong number of arguments (given 2, expected 1)` on read — measured at 866 errors
and 9 failures, the first being any `ActiveStorage::Blob#custom_metadata` read, i.e. any
attachment upload. Nothing in this app calls a removed json 3 API (checked: `fast_generate`,
`unparse`, `restore`, `GenericObject`, `create_additions`, `escape_slash`, `JSON.load`/`JSON.dump`
— none are used), so the blocker is entirely upstream.

**This one needed a Gemfile constraint**, unlike the rest of this file: `json` is an
unconstrained direct dependency, so bundler resolved it to 3.0.2 on its own. It is pinned
`gem "json", "< 3"` with a comment pointing here.

**To land it:** a Rails release whose `ActiveSupport::JSON.decode` calls `JSON.parse` with
keywords. Then delete the constraint and its comment and re-run `bundle update json`.

## `active_storage_validations` 4 — landed, with its new `accept` behaviour switched off

Not deferred: **4.1.1 is in.** Recorded here because of the flag it needed. 4.0 began deriving an
HTML `accept` attribute on every `file_field` from its model's content_type validator, which is
switched off in `config/initializers/active_storage_validations.rb`:
`Attachment::ALLOWED_CONTENT_TYPES` is deliberately a server-side allow-list, and roughly half of
it is types no browser knows (`application/x-musescore`, `application/x-sibelius`,
`text/x-lilypond`, `text/vnd.abc`), so a derived `accept` greys out files the server would have
taken. `test/models/attachment_test.rb` pins it. Turning it on is a real UX win but wants a pass
over every upload form first.

4.0 also gave analyzer commands (ffprobe, pdfinfo, identify, libvips) a 10s `command_timeout` that
fails closed. Left at the default — receipt photos and PDFs analyse well inside it — but that is
the knob if a large upload ever starts reporting an unreadable file.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby) — blocked by an upstream constraint

**Why deferred:** transitive. `solargraph` (still 0.60.4 after the 2026-09-21 sweep) constrains it
to `~> 1.4`, so 2.0.0 cannot resolve. No action needed here; it moves when solargraph does.

## `rdoc` 7.2.0 → 8.0.0 (Ruby) — blocked by the same upstream constraint

**Why deferred:** `solargraph` 0.60.4 still pins `rdoc (~> 7.0)`. We declare `rdoc` directly
(`group :development, :test`), but bundler cannot resolve 8.x while solargraph is in the bundle —
`bundle update rdoc` reports "attempted to update rdoc but its version stayed the same". When
solargraph widens the bound, note that **RDoc 8 drops the Ripper-based parser for Prism** and
removes deprecated CLI options/directives; nothing here drives rdoc programmatically, so the bump
should be inert for us.

## `highline` 3.0.1 → 3.1.2 (Ruby) — blocked by an upstream constraint

**Why deferred:** transitive via `commander` 5.0.0, which pins `highline (~> 3.0.0)` — a
pessimistic constraint at the patch level, so even 3.1.x is out. Moves when commander does.

## `rack-mini-profiler` 4 → 5 — landed 2026-09-21

Not deferred, noted for completeness: development/test only, so it gates nothing. The one break in
5.0 is a Ruby >= 3.2 floor (we're on 4.0.2) and no config options were removed.

## Not attempted, and why

- **`bundle exec vite upgrade` moves `vite` and `vite-plugin-ruby` from `dependencies` to
  `devDependencies`, and that was reverted on purpose.** It is vite_ruby's own convention and it
  is safe *today* only because the Dockerfile never sets `NODE_ENV` — so `pnpm install
  --frozen-lockfile` (Dockerfile:80) still installs dev deps and `rails assets:precompile`
  (Dockerfile:100) can find vite. Setting `NODE_ENV=production` in that image, an obvious-looking
  optimisation, would then break the asset build with "vite: not found". If the move is wanted, do
  it together with an explicit `pnpm install --prod=false` in the Dockerfile.
- **pnpm 11.9.0 → 12.5.1** was offered by the CLI and not taken: `packageManager` in
  `package.json` is the single source of truth and is bumped with `corepack use pnpm@<version>`,
  which rewrites the integrity hash. That is its own change, not a dependency sweep.

## Held back by the supply-chain cooldown — not deferred, just young

pnpm applies a 4-day `minimumReleaseAge`, so a release newer than that is skipped **by design**
and lands on the next sweep. At the 2026-07-31 sweep that was `vite` 8.2.0 (we took 8.1.5); at the
2026-09-21 sweep it was `vite-plugin-ruby` 5.2.4 and `eslint` 10.11.0. Nothing to do — do not
disable the cooldown to grab them.
