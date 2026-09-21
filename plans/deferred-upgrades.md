# Deferred dependency upgrades

Majors held back during the 2026-09-21 upgrade pass, with why and what unblocks them.
Everything else was taken to latest (see the `chore(deps)` commits of that date).

## `json` 2.21.2 → 3.x — blocked by Rails, constrained in the Gemfile

**Held at `< 3` in the Gemfile.** json 3 made `JSON.parse`'s options **keyword-only**:

```ruby
def parse(source, on_load: nil, object_class: nil, array_class: nil, **options)
```

Rails 8.1.3.1's `ActiveSupport::JSON.decode` still passes them positionally
(`activesupport/lib/active_support/json/decoding.rb:25`):

```ruby
data = ::JSON.parse(json, options)
```

So **every** serialized / JSON column raises `ArgumentError: wrong number of arguments
(given 2, expected 1)` on read — measured: 866 errors and 9 failures across the suite, the
first one being any `ActiveStorage::Blob#custom_metadata` read, i.e. any attachment upload.
Nothing in this app calls a removed json 3 API (checked: `fast_generate`, `unparse`,
`restore`, `GenericObject`, `create_additions`, `escape_slash`, `JSON.load`/`JSON.dump` —
none are used), so the blocker is entirely upstream.

**Unblocked by:** a Rails release whose `ActiveSupport::JSON.decode` calls `JSON.parse` with
keywords. Then delete the constraint and its comment from the Gemfile and re-run
`bundle update json`.

## `active_storage_validations` 3.0.5 → 4.1.1 — not attempted

Deliberately left for a pass of its own: it is the gem behind
`Attachment::ALLOWED_CONTENT_TYPES` and the receipt intake rules, so a major wants its
changelog read against `app/models/attachment.rb` and
`config/initializers/sheet_music_mime_types.rb` (the Marcel registration the allow-list
depends on) rather than a bump-and-see. Unconstrained in the Gemfile, so `bundle update
active_storage_validations` is all it takes once someone has read the 4.0 release notes.

## `rack-mini-profiler` 4.0.1 → 5.0.0 — not attempted

Development/test only, so it gates nothing. Same reason as above: its own pass.

## Notes from the same pass

- `rack-proxy` 0.8.3 → **2.0.1** did land, as a transitive bump: `vite_ruby` requires
  `>= 0.6.1` and the batch moved vite_ruby 3.10.2 → 3.11.0. It backs
  `ViteRuby::DevServerProxy`, which only sits in the middleware stack when a Vite dev
  server is running, and both suites are green with it.
- **`bundle exec vite upgrade` moves `vite` and `vite-plugin-ruby` from `dependencies` to
  `devDependencies`, and that was reverted on purpose.** It is vite_ruby's own convention
  and it is safe *today* only because the Dockerfile never sets `NODE_ENV` — so
  `pnpm install --frozen-lockfile` (Dockerfile:80) still installs dev deps and
  `rails assets:precompile` (Dockerfile:100) can find vite. Setting `NODE_ENV=production`
  in that image, an obvious-looking optimisation, would then break the asset build with
  "vite: not found". If the move is wanted, do it together with an explicit
  `pnpm install --prod=false` in the Dockerfile.
- pnpm's supply-chain cooldown held back `vite-plugin-ruby` 5.2.4 and `eslint` 10.11.0 as
  younger than 4 days. They are not deferred, just next time.
