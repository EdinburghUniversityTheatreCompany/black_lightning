# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

## database_consistency — schema-migration backlog (gate still advisory)

`database_consistency` is the one dev-env gate not yet driven to zero, so it stays advisory
(`|| true` in `hk.pkl` / `ci.yml`). The model-level findings are already fixed (144 `length`
validations) and the legacy integer-PK checkers are scoped out in `.database_consistency.yml`;
what remains (~170 findings) is a real **schema-migration project**:

- `ColumnPresenceChecker` (101 → add NOT NULL), `ForeignKeyChecker` (22 → add FKs),
  `MissingUniqueIndexChecker` (21), `ThreeStateBooleanChecker` (15 → NOT NULL boolean + default),
  plus the remaining index checkers.
- These need **data-aware backfill migrations on the legacy production DB** (columns may contain
  nulls / duplicates), which `strong_migrations` correctly blocks as unsafe and which need a
  production data audit. Do them as guarded multi-step migrations (backfill → add constraint) once
  the data is verified, then drop the `|| true` to make the gate enforce. Note the legacy
  integer-PK FK columns can't take a `t.references ... type: :integer` FK trivially.

## Upstream a mise-driven devcontainer template into dev-hooks

- Consider upstreaming devcontainer-mise support into the `dev-hooks:dev-env-setup` skill: it
  already standardises mise + hk + CI, but doesn't yet template a mise-driven `.devcontainer/`.
  (This is a change to the dev-hooks plugin marketplace, not to this repo.)

## Prune ruby-build-only apt packages from the devcontainer (needs a bundle-install test)

Now that Ruby is installed precompiled (`compile = false`, jdx/ruby), the packages in
`.devcontainer/Dockerfile.dev` that existed *only* to build CRuby from source via ruby-build —
`autoconf`, `libreadline-dev`, `libgdbm-dev`, `libncurses-dev`, `libgmp-dev`, `uuid-dev` — are
no longer needed for Ruby itself. They appear unused by the app's compiling native gems
(bcrypt, bcrypt_pbkdf, mysql2, nio4r, puma, json, prism, racc), so they're *probably* removable.
Keep `build-essential`, `libssl-dev`, `zlib1g-dev`, `libyaml-dev`, `libffi-dev`,
`libmariadb-dev-compat`, `pkg-config` (native gem builds). Before removing anything, verify with a
real `bundle install` in a trixie container using the pruned set — don't remove on inspection alone.
Payoff is modest (small image/layer shrink); the Ruby-compile time saving is already captured.
