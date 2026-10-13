# Deferred dependency upgrades

Upgrades that could **not** be applied during a dependency sweep, with the reason and what lands
them. Last reviewed: **2026-09-21**.

Every Ruby entry below is blocked by a constraint outside this repo. Re-check with
`bundle outdated` / `pnpm outdated`: anything still listed here is expected to appear.

## `json` 2.21.2 → 3.x (Ruby): blocked by Rails, and now constrained in the Gemfile

**Why deferred:** json 3 made `JSON.parse`'s options **keyword-only**
(`parse(source, on_load:, object_class:, array_class:, **options)`), while Rails 8.1.3.1's
`ActiveSupport::JSON.decode` still passes them positionally (`::JSON.parse(json, options)` at
`active_support/json/decoding.rb:25`). So **every** serialized / JSON column raises
`ArgumentError: wrong number of arguments (given 2, expected 1)` on read, measured at 866 errors
and 9 failures. The first is any `ActiveStorage::Blob#custom_metadata` read, i.e. any
attachment upload. Nothing in this app calls a removed json 3 API (checked: `fast_generate`,
`unparse`, `restore`, `GenericObject`, `create_additions`, `escape_slash`, `JSON.load`/`JSON.dump`:
none are used), so the blocker is entirely upstream.

**This one needed a Gemfile constraint**, unlike the rest of this file: `json` is an
unconstrained direct dependency, so bundler resolved it to 3.0.2 on its own. It is pinned
`gem "json", "< 3"` with a comment pointing here.

**To land it:** a Rails release whose `ActiveSupport::JSON.decode` calls `JSON.parse` with
keywords. Then delete the constraint and its comment and re-run `bundle update json`.

## `active_storage_validations` 4: landed, with its new `accept` behaviour switched off

Not deferred: **4.1.1 is in.** Recorded here because of the flag it needed. 4.0 began deriving an
HTML `accept` attribute on every `file_field` from its model's content_type validator, which is
switched off in `config/initializers/active_storage_validations.rb`:
`Attachment::ALLOWED_CONTENT_TYPES` is deliberately a server-side allow-list, and roughly half of
it is types no browser knows (`application/x-musescore`, `application/x-sibelius`,
`text/x-lilypond`, `text/vnd.abc`), so a derived `accept` greys out files the server would have
taken. `test/models/attachment_test.rb` pins it. Turning it on is a real UX win but wants a pass
over every upload form first.

4.0 also gave analyzer commands (ffprobe, pdfinfo, identify, libvips) a 10s `command_timeout` that
fails closed. Left at the default, since receipt photos and PDFs analyse well inside it, but that is
the knob if a large upload ever starts reporting an unreadable file.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby): blocked by an upstream constraint

**Why deferred:** transitive. `solargraph` (still 0.60.4 after the 2026-09-21 sweep) constrains it
to `~> 1.4`, so 2.0.0 cannot resolve. No action needed here; it moves when solargraph does.

## `rdoc` 7.2.0 → 8.0.0 (Ruby): blocked by the same upstream constraint

**Why deferred:** `solargraph` 0.60.4 still pins `rdoc (~> 7.0)`. We declare `rdoc` directly
(`group :development, :test`), but bundler cannot resolve 8.x while solargraph is in the bundle:
`bundle update rdoc` reports "attempted to update rdoc but its version stayed the same". When
solargraph widens the bound, note that **RDoc 8 drops the Ripper-based parser for Prism** and
removes deprecated CLI options/directives; nothing here drives rdoc programmatically, so the bump
should be inert for us.

## `highline` 3.0.1 → 3.1.2 (Ruby): blocked by an upstream constraint

**Why deferred:** transitive via `commander` 5.0.0, which pins `highline (~> 3.0.0)`, a
pessimistic constraint at the patch level, so even 3.1.x is out. Moves when commander does.

## Not attempted, and why

- **`bundle exec vite upgrade` moves `vite` and `vite-plugin-ruby` from `dependencies` to
  `devDependencies`, and that was reverted on purpose.** It is vite_ruby's own convention and it
  is safe *today* only because the Dockerfile never sets `NODE_ENV`, so `pnpm install
  --frozen-lockfile` (Dockerfile:80) still installs dev deps and `rails assets:precompile`
  (Dockerfile:100) can find vite. Setting `NODE_ENV=production` in that image, an obvious-looking
  optimisation, would then break the asset build with "vite: not found". If the move is wanted, do
  it together with an explicit `pnpm install --prod=false` in the Dockerfile.
- **pnpm 11.9.0 → 12.5.1** was offered by the CLI and not taken: `packageManager` in
  `package.json` is the single source of truth and is bumped with `corepack use pnpm@<version>`,
  which rewrites the integrity hash. That is its own change, not a dependency sweep.

## Held back by the supply-chain cooldown: not deferred, just young

pnpm applies a 4-day `minimumReleaseAge`, so a release newer than that is skipped **by design** and
lands on the next sweep. Nothing to do, and do not disable the cooldown to grab one.
