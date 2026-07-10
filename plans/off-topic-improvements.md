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

## Admin::MembershipCardsController is unrouted dead code

`admin/membership_cards` has **no routes** — the `resources :membership_cards` line in
`config/routes.rb` is commented out (~line 233) and `bin/rails routes -c admin/membership_cards`
returns nothing. The controller (whose own header says "Has been severely neglected. Can probably
use the GenericController.") and its views (`index`/`show`/`_index_results`) are therefore
unreachable. Its `index` still renders the unguarded `shared/pages/index` turbo_stream fragment, but
that's moot while unrouted. Decide to either **remove** the controller + views + empty test, or
**wire it up** (route it and convert to `GenericController`, which already guards the index
turbo_stream via `render_index_stream_or_full`). Left untouched for now since it can't be triggered.

## Opportunity show contact line drops the viewer context

`app/views/admin/opportunities/show.html.erb`'s contact field calls
`@opportunity.submitter_display_name` **without** passing `@current_user`, unlike the other
call sites (`OpportunityCardComponent`, the created_by field before it was restructured), so
`User#name(current_user = nil)` renders the creator's name without viewer-aware formatting.
Probably harmless (admins see full names anyway), but inconsistent — pass `@current_user` or
document why it's omitted. Also, `Opportunity#css_class` calls `.html_safe` on the literal
strings `"table-success"`/`"table-danger"` for no reason; plain strings would do.

## CarouselItem#tagline: authored as Markdown but rendered as plain text (inconsistent)

`CarouselItem#tagline` is edited through the `Admin::MdEditorComponent` Markdown editor
(`app/views/admin/carousel_items/_form.html.erb:6`) but is output raw, NOT through
`render_markdown`, in `app/components/public/basic_info_component.html.erb:11`. So a tagline like
`**bold**` or `##Heading` shows up literally on the public carousel rather than as formatted HTML —
the opposite of every other Markdown column in the app. Because of this mismatch it was
deliberately **excluded** from the `markdown:fix_heading_spaces` cleanup task
(`lib/tasks/logic/markdown_heading_fix.rb` `TARGETS`): inserting a space there would visibly change
the literal string users see rather than fix a heading.

Pick one and make it consistent:
- **Render it as Markdown** — swap the raw output for `render_markdown(@tagline)` (or
  `render_plain`/`truncate_markdown` if only inline emphasis is wanted, no block elements). Then
  add `CarouselItem => [:tagline]` back into the cleanup task's `TARGETS`.
- **Or stop making it Markdown-authorable** — replace the `Admin::MdEditorComponent` with a plain
  `f.input :tagline` text field, since a one-line carousel tagline arguably doesn't need Markdown.

Recommended: the plain-text-field route (a hero tagline is short and rarely needs block Markdown),
which also removes the heavyweight editor from a trivial field. Either way, resolve the
edit-as-Markdown / render-as-plain contradiction.

---

## RubyLLM legacy `acts_as` deprecation warning on boot (Phase B)

Since introducing `ruby_llm`, every process load prints:
`RubyLLM's legacy acts_as API is deprecated and will be removed in RubyLLM 2.0.0`.
We don't use `acts_as_chat`/`acts_as_message` (the Extractor and AiChecker call
`RubyLLM.chat` directly), so the warning is pure noise from the gem's Rails engine.
Investigate silencing it (config flag or a targeted `ActiveSupport::Deprecation`
filter) so test/boot output stays clean. Harmless; not gating.
