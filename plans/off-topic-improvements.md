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

## Production Dockerfile is not mise-driven

- The dev container now installs the mise-pinned toolchain (`mise.toml`/`mise.lock` as single
  source of truth). The **production** [Dockerfile](Dockerfile) still hard-codes Node via
  nodesource (`ARG NODE_VERSION=22`) and Ruby via the `ruby:4.0.2-slim` base — so prod can drift
  from `.node-version` (24.13.0) / `mise.toml` just like the dev container did. Consider making
  the prod build mise-driven too (or at least bumping `NODE_VERSION` to match and adding a check),
  so all three environments (host, dev container, prod) share one pinned Node/Ruby.
- Consider upstreaming devcontainer-mise support into the `dev-hooks:dev-env-setup` skill: it
  already standardises mise + hk + CI, but doesn't yet template a mise-driven `.devcontainer/`.
