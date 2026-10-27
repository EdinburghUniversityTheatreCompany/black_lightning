# Deferred dependency upgrades

Upgrades that could **not** be applied during a dependency sweep, with the reason and what lands
them. Last reviewed: **2026-10-27**.

Every Ruby entry below except `doorkeeper-openid_connect` is blocked by a constraint outside this
repo. Re-check with
`bundle outdated` / `pnpm outdated`: anything still listed here is expected to appear.

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

## `doorkeeper-openid_connect` 1.10.5 → 2.1.0 (Ruby): prepared, waiting for a review

**Why held:** it is the OpenID provider behind the pretix shop's member login, so a regression
locks members out of member pricing (see "Pretix membership sync" in AGENTS.md). The upgrade is the
last commit on the `deps-upgrade` branch. A code → token → id_token → userinfo → discovery run
through the real initializer gave identical output on both versions (token fields, id_token claims,
`sub` as the user id, userinfo's `email`, JWKS) except one new discovery field,
`authorization_response_iss_parameter_supported: false`. It needs no migration: 2.0's
`post_logout_redirect_uris` column is only for RP-Initiated Logout, which this app does not use, and
the gem skips the column when it is absent. Merge that commit and delete this entry.

## `diff-lcs` 1.6.2 → 2.0.0 (Ruby): blocked by an upstream constraint

**Why deferred:** transitive. `solargraph` (0.61.0 after the 2026-10-27 sweep) still constrains it
to `~> 1.4`, so 2.0.0 cannot resolve. No action needed here; it moves when solargraph does.

## `rdoc` 7.2.0 → 8.1.0 (Ruby): blocked by the same upstream constraint

**Why deferred:** `solargraph` 0.61.0 still pins `rdoc (~> 7.0)`. We declare `rdoc` directly
(`group :development, :test`), but bundler cannot resolve 8.x while solargraph is in the bundle:
`bundle update rdoc` reports "attempted to update rdoc but its version stayed the same". When
solargraph widens the bound, note that **RDoc 8 drops the Ripper-based parser for Prism** and
removes deprecated CLI options/directives; nothing here drives rdoc programmatically, so the bump
should be inert for us.

## `highline` 3.0.1 → 3.1.2 (Ruby): blocked by an upstream constraint

**Why deferred:** transitive via `commander` 5.0.0, which pins `highline (~> 3.0.0)`, a
pessimistic constraint at the patch level, so even 3.1.x is out. commander 6.0.0 exists, but
`sord` 7.1.0 (solargraph's) pins `commander (~> 5.0)`. Moves when sord does.

## Other transitive majors, each held by the gem that depends on it

`marcel` 2 (Rails pins `~> 1.0`), `net-ssh` 8 (sshkit, `< 8.0.0`), `prism` 2 (rubocop-ast,
ruby-lsp and solargraph, `< 2.0` / `~> 1.x`) and `open3` 0.3 (solargraph, `~> 0.2.1`). Nothing to do
here; `bundle outdated` lists them until their dependents widen.

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

pnpm applies a 4-day `minimumReleaseAge`, Bundler the Gemfile's `cooldown: 4` and pinact
`-m 4`, so a release newer than that is skipped **by design** and lands on the next sweep. Do not
disable the cooldown to grab one, except for a security fix someone has decided is urgent.

On 2026-10-27 that held back **ransack 6.0.1** (published 2026-10-25), the fix for
GHSA-58rx-96gf-w92x, a reflected XSS and open redirect through `sort_link`, which `TableComponent`
renders on every admin table. It leaves the cooldown on 2026-10-29; once the advisory reaches
ruby-advisory-db, CI's bundler-audit fails until it is in.
