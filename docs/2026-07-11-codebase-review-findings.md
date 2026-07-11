# Codebase Review — Findings (2026-07-11)

A whole-codebase review of the Black Lightning Rails 8 app, run along the axes
described by the `code-review` skill: **correctness**, **security/authorization**,
**reuse/duplication**, **simplification**, **efficiency**, **altitude** (is the fix at
the right depth), and **conventions** (CLAUDE.md).

The review fanned out across five domains — models & authorization, controllers,
services/jobs/mailers, views/components/helpers, and JavaScript & config/security.
Every finding names a concrete failure scenario. Findings marked **✓ verified** were
re-read against source and the failure mode confirmed by hand during this review; the
rest are high-confidence reports from the domain passes and are worth a quick confirm
before fixing.

> Nothing here has been changed — this is a findings report only. Items are ordered by
> severity within each section. Line numbers are as of commit `76ebbd2`.

---

## Summary

| # | Severity | Axis | Area | Finding |
|---|----------|------|------|---------|
| 1 | **High** | security | Controllers | `POST /markdown/upload` is fully anonymous — arbitrary S3 attachment writes + IDOR ✓ |
| 2 | **High** | security | Views | Stored XSS on the opportunity show page via public-submitted `role.note` / `department_name` / `submitter_name` ✓ |
| 3 | **High** | correctness | Models | Debt conversion uses `create` (not `create!`) inside a txn → debt silently written off ✓ |
| 4 | **High** | correctness | Jobs | Mailbox poll move is outside the dedup rescue → duplicate draft expense every 5 min ✓ _(acknowledged — fix already planned)_ |
| 5 | Medium | security | Controllers | `dashboard#widget` has no env guard and reflects `params` into `html_safe` (reflected XSS) ✓ |
| 6 | Medium | security | Config | CSP allows `unsafe-inline` + `unsafe-eval` in production, negating XSS protection |
| 7 | Medium | security | Controllers | Public `get_involved#opportunities` Ransack omits `auth_object` ✓ |
| 8 | Medium | security | Models | `User#absorb` lets an `:absorb` grantee inherit an admin's non-Admin roles (privilege escalation) |
| 9 | Medium | correctness | Config | CORS subdomain origin is a String-that-looks-like-a-Regexp → never matches ✓ |
| 10 | Medium | correctness | Models | `Email` normalize lambda has a `&.` precedence bug → `NoMethodError` on nil ✓ |
| 11 | Medium | correctness | Models | `Company.find_or_build_by_name` TOCTOU → 500 on concurrent public submissions |
| 12 | Medium | correctness | Mailers | `DebtMailer` creates the audit record before delivery → duplicate rows on retry |
| 13 | Medium | efficiency | Controllers | `GenericController` `X-Total-Count` uses `.count` on a paginated relation (wrong value + extra query) ✓ |
| 14 | Medium | correctness | Services | `Store#fetch_expense` partially seeds `@expenses` → later `#expenses` returns an incomplete list |
| 15 | Medium | efficiency | Services | `Store#fetch_list` has no stampede protection → cache-miss bursts burn the Airtable budget |
| 16 | Medium | altitude | Controllers | `GenericController#update` string-matches one model's DB constraint in the shared base |
| 17 | Medium | correctness | JS | `markdown#preview` `CGI.unescape`s un-encoded JSON input → corrupts `+` and `%` |
| — | Low | various | — | 20+ lower-severity items — see [Low-severity findings](#low-severity-findings) |

---

## High severity

### 1. `POST /markdown/upload` is fully anonymous ✓
**`app/controllers/markdown_controller.rb:24`** · security

`MarkdownController` calls `skip_authorization_check` and `ApplicationController` has no
global `authenticate_user!` (it only runs CanCanCan's `check_authorization`, which
`skip_authorization_check` disables). The route `POST /markdown/upload`
(`config/routes.rb:388`) is therefore reachable by any anonymous visitor.

- Anyone can upload image files to Wasabi/S3 (paid storage) with no rate or size limit.
- `resolve_item(params[:item_type], params[:item_id])` (line 56) will `constantize` any
  `ApplicationRecord` subclass and attach the new public (`access_level: 2`) `Attachment`
  to **any** record addressed by id — an IDOR / arbitrary-attachment-injection vector.

**Fix:** add `before_action :authenticate_user!` and an `authorize!` on the resolved item
(or on `Attachment`); scope the action to backend users.

### 2. Stored XSS on the opportunity show page ✓
**`app/views/admin/opportunities/show.html.erb:5-6, 34`** · security

Opportunity submission is public (`GetInvolvedController#create`, logged-out submitters).
`get_involved_controller.rb:80-84` permits `roles_attributes: [:position, :department_name,
:note, …]` plus `:submitter_name` from anonymous users. The show page then marks those
attacker-controlled strings as `html_safe`:

```erb
label += " — #{role.department.name}".html_safe if role.department
label += " (#{role.note})".html_safe if role.note.present?
...
"You can contact #{@opportunity.submitter_display_name} by emailing them at #{mail_to display_email}.".html_safe
```

A submitter entering `<img src=x onerror=...>` as a role note or submitter name stores
XSS that fires in the reviewer/admin's browser. (Line 4 already does the right thing with
`content_tag(:strong, role.position)`.)

**Fix:** escape the values — e.g. `safe_join(["You can contact ", submitter_display_name,
" by emailing them at ", mail_to(display_email), "."])`; wrap `note`/`department.name` in
`content_tag`/`safe_join` so only the intended markup is safe.

### 3. Debt conversion uses `create` instead of `create!` ✓
**`app/models/admin/maintenance_debt.rb:82`** (mirror: `admin/staffing_debt.rb:112`) · correctness

```ruby
def convert_to_staffing_debt
  ActiveRecord::Base.transaction do
    Admin::StaffingDebt.create(due_by:, show_id:, user_id:, state: :normal, converted_from_maintenance_debt: true)
    update(state: :converted, maintenance_credit: nil)   # runs even if the create failed validation
  end
end
```

`create` returns an unsaved object on validation failure without raising, so the
transaction still commits the `state: :converted` update — the original debt is written
off with **no replacement debt created** (debt evasion / data loss). Reached from
`admin/maintenance_debts_controller.rb:51` and `admin/staffing_debts_controller.rb:52`.

**Fix:** use `create!` so a failure rolls back the whole transaction.

### 4. Mailbox poll can mint a duplicate expense every 5 minutes ✓
**`app/jobs/reimbursements/mailbox_poll_job.rb:130`** · correctness · _acknowledged by maintainer — fix already planned, not re-flagged in later rounds_

`create_expense` calls `store.create_expense!` then wraps attach+reply in a
`begin/rescue`, but the committing `mailbox.mark_read_and_move(message.id, :processed)`
sits **outside** that rescue (line 130), and `MailboxClient::AuthError` is explicitly
re-raised (line 122). If the move (or a re-raised auth error) fails, the exception
propagates to `process`'s handler, which logs and leaves the message **unread** — even
though the expense already exists. The next 5-minute poll re-runs `create_expense` and
creates a **duplicate draft expense**, breaking the CLAUDE.md invariant that reply-then-move
is the single commit point.

**Fix:** make the move the first irreversible commit step, or dedupe by persisting the
source message-id on the expense and skipping messages whose expense already exists.

---

## Medium severity

### 5. `dashboard#widget` — reflected XSS, no environment guard ✓
**`app/controllers/admin/dashboard_controller.rb:7`**, **`app/helpers/admin/dashboard_helper.rb:18`** · security

The action's comment claims it's "only accessible in dev and test," but neither the
controller nor `routes.rb:373` has any `Rails.env` guard — it is live in production for any
backend user. `dashboard_widget(params[:widget_name])` interpolates the raw name into an
`.html_safe` "Widget Not Found" string on `MissingTemplate`, and the name is also used as a
user-controlled render path. A crafted `widget_name` yields reflected XSS against a
logged-in admin.

**Fix:** guard the route/action to non-production and HTML-escape `name` in the helper.

### 6. CSP allows `unsafe-inline` and `unsafe-eval` in production
**`config/initializers/content_security_policy.rb:10`** · security

`script_src` includes both `:unsafe_inline` and `:unsafe_eval` unconditionally, and the
nonce generator is commented out. This defeats CSP's main purpose: any stored/reflected XSS
(see #2, #5) can still execute inline `<script>` and eval payloads.

**Fix:** drop `:unsafe_inline` (move to nonces via `content_security_policy_nonce_generator`)
and remove `:unsafe_eval` unless a specific dependency needs it.

### 7. Public `get_involved#opportunities` Ransack omits `auth_object` ✓
**`app/controllers/get_involved_controller.rb:10`** · security

`Opportunity.listable.ransack(params[:q])` runs on a fully public endpoint without
`auth_object: current_ability` — unlike `GenericController#base_index_ransack_query`, which
passes it. `Opportunity.ransackable_attributes` ignores its `auth_object` arg and exposes
`contact_email`, `email_visibility`, `approved`, and the `creator`/`company` associations to
anonymous predicate queries (blind enumeration of emails, probing non-public rows).

**Fix:** pass `auth_object: current_ability` and make `ransackable_attributes`/`_associations`
return a public-only allow-list when `auth_object` can't manage the model.

### 8. `User#absorb` privilege escalation
**`app/models/user.rb:652`** · security

The role-merge loop skips only `role.name == "Admin"`; every other role on the absorbed
user is added to the target. A user with the `:absorb` grid permission can merge an
account and acquire its Committee / Opportunity Reviewer / finance roles. The code comment
calls this "acceptable," but the escalation is real and non-obvious.

**Fix:** gate absorb-of-privileged-users in `Ability`, or exclude privileged roles from the
union.

### 9. CORS subdomain origin is a String, not a Regexp ✓
**`config/initializers/cors.rb:3`** · correctness

```ruby
origins "localhost:3000", "127.0.0.1:3000", '/(.+?)\.bedlamtheatre\.co\.uk', "bedlamtheatre.co.uk", ...
```

`'/(.+?)\.bedlamtheatre\.co\.uk'` is a **string literal**, not a `Regexp`. Rack::Cors
matches string origins literally (only `*` is special), so this entry never matches any
real `Origin` and all `*.bedlamtheatre.co.uk` subdomains silently get no CORS headers —
broken intent. (The failure is fail-safe rather than permissive, hence Medium.) The
`resource "*"` block also grants `headers: :any` and all methods.

**Fix:** use an actual Regexp (`%r{\Ahttps?://(.+?)\.bedlamtheatre\.co\.uk\z}`) and tighten
methods/headers.

### 10. `Email` normalize lambda `&.` precedence bug ✓
**`app/models/email.rb:28`** · correctness

```ruby
normalizes :email, with: ->(email) { email&.downcase.strip }
```

Parses as `(email&.downcase).strip`; when `email` is nil this is `nil.strip` → `NoMethodError`
rather than a clean presence-validation failure. `NewsletterSubscriber` and `Venue`
correctly chain `email&.downcase&.strip`.

**Fix:** `email&.downcase&.strip`.

### 11. `Company.find_or_build_by_name` TOCTOU
**`app/models/company.rb:48`** · correctness

`find_by(...) || new(name:)` + `acts_as_url :name` means two concurrent public opportunity
submissions naming the same new company both find nothing, both derive slug `foo`, and the
second insert violates the unique `companies.slug` index — an unhandled `RecordNotUnique`
(500) on a public endpoint.

**Fix:** rescue `RecordNotUnique` and retry the find, or use upsert semantics.

### 12. `DebtMailer` creates the audit record before delivery
**`app/mailers/debt_mailer.rb:14`** · correctness

`mail_debtor` calls `Admin::DebtNotification.create(...)` while building the message. Via
`deliver_later` + `ApplicationJob`'s retry (5–10×), a transient SMTP failure re-invokes the
mailer and creates another `DebtNotification` row per attempt, inflating history and
mis-driving "already notified" logic.

**Fix:** record after successful delivery (observer/callback), or make it idempotent
(`find_or_create` keyed on user+date+type).

### 13. `X-Total-Count` uses `.count` on a paginated relation ✓
**`app/controllers/generic_controller.rb:17`** · efficiency

`load_index_resources` returns a Kaminari page; `resources.count` issues a COUNT that
honours LIMIT/OFFSET, so the header reports the per-page count (≤30), not the true total —
plus an extra COUNT query on essentially every index page in the app. No reader for the
header exists in the codebase.

**Fix:** use `resources.total_count` when paginated, or drop the header.

### 14. `Store#fetch_expense` partially seeds the memoized list
**`app/services/reimbursements/store.rb:172`** · correctness

`@expenses = ((@expenses || []).reject{…} + [expense])`. On a fresh Store (e.g.
`remove_receipt!` → `fetch_expense` directly, not via `find_expense!`), `@expenses` becomes
a one-element array; a later `store.expenses` hits `@expenses ||= …` and returns just that
one record, silently dropping every other expense from the request.

**Fix:** don't seed `@expenses` from a single-record fetch unless the full list was already
loaded; track fetched singletons separately.

### 15. `Store#fetch_list` has no cache-stampede protection
**`app/services/reimbursements/store.rb:154`** · efficiency

`@cache.fetch(key, expires_in: ttl)` (Solid Cache) has no lock / `race_condition_ttl`. When
the 10-minute `EXPENSES_KEY` expires, every concurrent request that misses calls
`list_records`, so one expiry can cost N paginated Airtable calls against the ~1,000/month
free-plan budget (shared with bedlam-bacs).

**Fix:** single-flight lock around the refetch, or stale-while-revalidate.

### 16. `GenericController#update` special-cases one model's DB constraint
**`app/controllers/generic_controller.rb:102`** · altitude

The shared base rescues `RecordNotUnique` and string-matches the literal `team_members` +
`teamwork_and_user` index to convert it to a base error; every other `RecordNotUnique`
re-raises (500). This bandaid lives in the base that dozens of resources inherit and drifts
if the index is renamed.

**Fix:** move uniqueness handling into the model validation or a per-controller hook.

### 17. `markdown#preview` `CGI.unescape`s un-encoded input
**`app/controllers/markdown_controller.rb:17`** · correctness

`preview` does `CGI.unescape(body["input_html"])`, but the only caller
(`markdown_editor_controller.js#loadPreview`) sends the raw textarea value inside
`JSON.stringify` — not URL-encoded. `CGI.unescape` turns `+` into space and decodes any
`%XX`, so previewing markdown containing `C++` or `50% off` renders differently from what is
saved.

**Fix:** use `body["input_html"]` directly.

---

## Low-severity findings

Grouped by area. These are worth fixing opportunistically or batching.

### Models & authorization
- **`admin/staffing_debt.rb:76`** — `formatted_status` references undefined `local_status` → `NameError` if ever called (currently dead). Use `status`.
- **`admin/staffing_debt.rb:38`** — `ransackable_attributes` whitelists non-columns `converted`/`forgiven` (the column is `state`); `q[converted_eq]=1` raises.
- **`complaint.rb:34`** — `ransackable_attributes` returns `nil` (not `[]`) when unauthorized and calls `.can?` on a nil default `auth_object` → `NoMethodError`. Guard `auth_object&.can?` and return `[]`.
- **`newsletter_subscriber.rb:22`** — unique email index but no uniqueness/format validation; public repeat signup raises `RecordNotUnique` instead of a clean error.
- **`marketing_creatives/profile.rb:32`** — case-sensitive name uniqueness conflicts with downcasing `acts_as_url` slug → confusing error on the wrong field.
- **`opportunity_role.rb:51`** — `default_scope { order(:ordering) }` on a nullable column: nondeterministic order that leaks into all associations. Prefer an explicit `.ordered` scope.
- **`venue.rb:48`** — `normalizes :email` on a model with no `email` column (dead/misleading).
- **`concerns/debt_management.rb:121`** — `sync_debts_for_all_users` issues two COUNT queries per team member (N+1); replace with one grouped count.
- **`ability.rb:29`** — `begin/rescue/ensure` used as control flow (the real `can` call is in `ensure`); rewrite as a normal rescue.

### Controllers
- **`admin/users_controller.rb:42`** — `flash[:succes]` typo → password-reset confirmation never renders. Use `:success`.
- **`admin/users_controller.rb:168`** — `permitted_params` mutates `params` in place and runs a bcrypt `valid_password?` as a side effect during authorization; make it pure.
- **`generic_controller.rb:380`** — `upload_dropzone` permits `access_level` from raw params (self-acknowledged in the comment): a user with update access can set arbitrary picture `access_level`/tag ids. Authorize `Picture` creation and validate `access_level`.
- **`admin/show_crew_imports_controller.rb:83`** — fuzzy-bucket confirm trusts an arbitrary user id from the posted action string (`link_<id>`) without checking it was a presented candidate.
- **`profile_completions_controller.rb:26`** — completion token is not invalidated after use; a leaked link remains a login-as-user vector via the token branch. Consume/rotate on completion.
- **`generic_events_controller.rb:11`** — `show` discards the already-authorized record and re-runs `find` with `includes` (redundant query per event show).
- **`admin/staffings_controller.rb:243`** — `sign_up`/`sign_up_confirm` skip authorize and gate only via a view helper's `user.can?`, bypassing `check_authorization`. Call `authorize!` explicitly.
- **`admin/membership_controller.rb:16`** — invalid `render :json, {…}` syntax in the card-not-activated branch (currently under `:nocov:`).

### Services / jobs / mailers
- **`airtable/client.rb:86`** — 429 handling sleeps a fixed 30s and retries only once, ignoring `Retry-After`, then raises a 500 rather than serving cache.
- **`credentials_check_job.rb:13`** — secret-expiry warning emails every day for 30 days with no dedup (unlike `MailboxPollJob`'s once-per-day alert). Throttle / send on threshold crossings.
- **`extractor.rb:116`** — Gemini API key placed in the URL query string rather than an `x-goog-api-key` header (proxy/access-log exposure risk).
- **`opportunity_mailer.rb:4`** — `expiry_reminder` dereferences `opportunity.creator` with no nil guard (unlike sibling actions); a nil-creator caller triggers `NoMethodError` retried 5×.
- **`refresh_cloudflare_ips_job.rb:23`** — `Net::HTTP.get` with no open/read timeout can hang a worker; reuse `HttpTransport`'s timeouts.
- **`store.rb:53`** — `find_expense!` refreshes a single record but never busts the shared list cache, so other processes serve the stale list for up to 10 min (documented, but a cross-process visibility gap).
- **`contact_form_mailer.rb:7`** — user-supplied `sender_email` flows into `to:`/`reply_to:` with no app-level validation (relies solely on the mail gem to reject header injection) and silently CCs the submitter.
- **`http_transport.rb:11`** (reuse) — non-2xx handling, single-429 retry, backoff, and body-truncation are re-implemented three times across `Client`, `Extractor`, `MailboxClient`; consolidate behind one retry-policy wrapper (this is where #4 and the 429 bug hide).

### JavaScript
- **`controllers/techie_graph_controller.js:176`** — catch handler calls `console.warning` (no such method; it's `console.warn`), so the localStorage-quota path this catch guards throws `TypeError` itself.
- **`controllers/dropzone_controller.js:77`** — `get addRemoveLinks()` returns `… || true`, always truthy (even `"false"`); the control can never be disabled.
- **`controllers/live_search_controller.js:52`** — `fetch().then().then()` with no `.catch` → unhandled promise rejection with no user feedback on network error.
- **`controllers/membership_checker_controller.js:32`** — uses global `Swal.fire` with no existence guard (other controllers guard `window.Swal`) → `ReferenceError` if SweetAlert2 hasn't loaded.
- **`controllers/merge_modal_controller.js` / `template_loader`** (reuse) — reimplement `<dialog>` open/close/backdrop logic that `modal_controller.js` already provides, in three places.

### Config / security
- **`config/database.yml:45`** — production DB password comes from `ENV['MYSQL_ROOT_PASSWORD']`; connecting as root means an app compromise has full DBA rights. Use a least-privilege app account.
- **`config/initializers/permissions_policy.rb:1`** — the entire Permissions-Policy config is commented out; no header is emitted. Consider a restrictive default.
- **`.github/workflows/ci.yml:151`** — the test job grants `actions: write` though its steps only need `actions: read`; every other job is `contents: read`. Drop to least privilege.
- **`app/views/layouts/_footer.html.erb:14`**, **`admin/venues/_form.html.erb:7`** — `target="_blank"` links without `rel="noopener"` (trusted URLs, but inconsistent with the rest of the codebase which sets `rel` explicitly).

### Views (escaping hygiene)
- **`users/show.html.erb:21`** & **`admin/users/show.html.erb:46`** — `"<b>Position</b>: #{team_membership.position}".html_safe` on a public profile marks the position value raw; also duplicated markup across the two show views (extract a shared partial). Lower trust than #2 (committee-entered) but same smell.
- **`admin/staffings/sign_up.turbo_stream.erb:2`** — `flash[:error].join("<br><br>").html_safe` marks the whole joined string safe; prefer `safe_join(flash[:error], tag.br + tag.br)`.
- **`shared/pages/public/partials/_card_paragraphs.erb:5-7`** — emits opening/closing `<small>` as two separate `html_safe` fragments around content (fragile; encourages callers to pass `html_safe` content). Use `content_tag(:small, …)`.
- **`admin/venues/show.html.erb:8`** — redundant `.html_safe` on `venue_map` output (already a SafeBuffer; marks the plain-text fallback as HTML too).

---

## Round 2 additions (2026-07-11)

A second pass targeting angles round 1 sampled only lightly: the data/money layer
(migrations, schema, ransackable audit, finance math), the breadth of `admin/**`
controllers + routes + jobs + mailers, and the quality axes (reuse/efficiency/dead-code)
across the whole app. The money/debt layer largely held up — BigDecimal is used
consistently, and the deliberate `nil`-prepended reallocation IN-lists are correct.
14 genuinely-new findings (deduped against round 1); none change the round-1 top four.

| # | Severity | Axis | Area | Finding |
|---|----------|------|------|---------|
| R2-1 | Medium | correctness | Jobs | `DailyMaintenanceJob` is monolithic under `retry_on StandardError` → a late-step failure re-emails every new debtor / expiring-opp creator (up to 5–10×) ✓ |
| R2-2 | Medium | correctness | Schema | `marketing_creatives_profiles.url` (the routing key) has a non-unique index → TOCTOU duplicate slugs, one profile unreachable ✓ |
| R2-3 | Medium | reuse | Helpers | `label_helper.rb` `BADGE_CLASS_MAP` duplicates `BadgeComponent::STYLES` (second source of truth for badge styling) ✓ |
| R2-4 | Medium | efficiency | Views | Dashboard "pending opportunities" relation is queried 3× per load (index badge + widget `any?` + widget `count`) ✓ |
| R2-5 | Medium | efficiency | Views | `_committee_staffing_widget` nested N+1 over every committee member + polymorphic `staffable` (evaluated twice) |
| R2-6 | Low | security | Controllers | `membership_imports#confirm` trusts an arbitrary `merge_<id>` user id from the posted action string (same class as show_crew_imports) |
| R2-7 | Low | correctness | Jobs | `MassMailJob` is not idempotent — a mid-loop failure re-enqueues the mass mail to already-processed members on retry |
| R2-8 | Low | correctness | Models | `admin/maintenance_debt.rb:49` ransackable whitelists association names `user`/`show` as attributes → `q[show_eq]=1` 500s (same class as staffing_debt:38) |
| R2-9 | Low | correctness | Schema | `admin_staffing_debts` (and maintenance_debts) have no DB-level FKs → orphaned `user_id` → nil `debt.user` → `NoMethodError` in callbacks |
| R2-10 | Low | efficiency | Jobs | `RefreshFuzzyBothDuplicatesJob` loads `User.all.to_a` and lumps all blank-last-name users into one O(n²) fuzzy-compare bucket |
| R2-11 | Low | efficiency | Helpers | `shared_debt_helper.rb:30` materialises all member ids into a giant `WHERE user_id IN (...)` on every debt index; use a subquery |
| R2-12 | Low | efficiency | Views | `_staffings_widget` fires 2 COUNT queries per row (10 extra queries); preload `staffing_jobs` and count in Ruby |
| R2-13 | Low | efficiency | Views | `_opportunities_widget:26,28` calls `.count` on an already-loaded relation; use `.size` |
| R2-14 | Low | efficiency | Controllers | `GenericController#return_random` `pluck(:id).sample` loads all matching ids into Ruby plus a redundant `present?` check; use DB-side random |

### R2-1. `DailyMaintenanceJob` retry storm re-emails debtors ✓
**`app/jobs/daily_maintenance_job.rb:4`** · correctness · Medium

`perform` runs 8 sequential steps in one job. `ApplicationJob` applies `retry_on
StandardError (5×)` and `retry_on Net::SMTP* (10×)` to the **whole** job. A failure in a
*late* step (`send_test_email` line 77, `honeybadger_checkin`) re-runs `perform` from the
top, re-executing `notify_debtors`. `new_debtors = debtors - User.in_debt(yesterday)`
(`lib/tasks/logic/debt.rb:24`) is guarded only by yesterday's debt state, **not** by
notification history (only `long_time_debtors` uses `notified_since`), so the same set is
re-derived and re-mailed each retry; `notify_expiring_opportunities` likewise re-sends.
Distinct from round-1 #12 (which is about `DebtNotification` *rows* at the mailer level).
**Fix:** decompose into separate idempotent jobs, and guard `new_debtors` by notification
history.

### R2-2. `marketing_creatives_profiles.url` missing unique index ✓
**`db/schema.rb:467`**, **`app/models/marketing_creatives/profile.rb:32`** · correctness · Medium

`Profile` uses `acts_as_url :name`, exposes `url` via `to_param`, and is loaded with
`find_by: :url`, with only an app-level `validates :url, uniqueness`. The schema index is
**non-unique** (contrast `companies.slug`, `db/schema.rb:302`, which is `unique: true`). Two
concurrent signups with the same name both derive slug `foo`, both pass the read-before-write
check, and both insert `url='foo'`; `find_by(url: 'foo')` then resolves ambiguously and one
profile becomes unreachable. Round-1's profile item (#low, case-sensitivity) is a different
angle. **Fix:** add a unique index on `marketing_creatives_profiles.url` and rescue
`RecordNotUnique` in create.

### R2-3. `BADGE_CLASS_MAP` duplicates `BadgeComponent` ✓
**`app/helpers/label_helper.rb:112`** · reuse · Medium

`BADGE_CLASS_MAP` (lines 112-125) hard-codes the same 8 class mappings
(`bg-success → "bg-success/15 text-success"`, …) and `generate_label` re-implements the
same `rounded-full`/`float-right` toggles already authoritative in
`app/components/badge_component.rb` (`STYLES` + `style_classes`, lines 2-23). Two copies
drift independently — the exact anti-pattern CLAUDE.md forbids for buttons. **Fix:** render
`BadgeComponent` from `generate_label`/`proposal_labels` and delete `BADGE_CLASS_MAP`.

### R2-4. Dashboard pending-opportunities queried three times ✓
**`app/views/admin/dashboard/index.html.erb:12`**, **`_opportunities_widget.html.erb:3,5,8`** · efficiency · Medium

The index header computes `Opportunity.where(approved: false).where("expiry_date > ?",
Date.current).count`; the widget then rebuilds the identical relation and evaluates it again
via `pending.any?` and `pending.count` — 3 near-identical COUNT/EXISTS queries per render.
**Fix:** compute the relation/count once (controller or memoized helper) and pass it in.

### R2-5. `_committee_staffing_widget` nested N+1
**`app/views/admin/dashboard/_committee_staffing_widget.html.erb:13`** · efficiency · Medium

`Role.where(name: "Committee").first.users` loads all committee members with no preloading;
per member `person.staffing_jobs.where(name: "Committee Rep")` is evaluated **twice** (lines
13 and 15), and each `.select { |j| j.staffable.start_time… }` lazily loads the polymorphic
`staffable` per job. Cost grows unbounded with committee size × jobs. **Fix:** preload
(`includes(staffing_jobs: :staffable)`), filter in Ruby/SQL, reuse the loaded set for both
semesters.

### R2 low-severity items
- **R2-6** `app/controllers/admin/membership_imports_controller.rb:119` (security) — `process_item` matches `merge_<id>` and does `User.find_by(id: $1)` then grafts the import row's email/student_id/associate_id and `:member` onto that user, without checking the id was one of the fuzzy candidates from `#preview`. A tampered form can corrupt any account. Validate against the presented candidate ids.
- **R2-7** `app/jobs/mass_mail_job.rb:10` (correctness) — `recipients.each { … deliver_later }` over all members; a mid-loop failure + `retry_on StandardError` re-runs `perform` from the start, re-enqueuing already-processed recipients (duplicate mass mail). Track sent recipients / enqueue the fan-out idempotently.
- **R2-8** `app/models/admin/maintenance_debt.rb:49` (correctness) — `ransackable_attributes` includes `user`/`show` (associations, not columns); `q[show_eq]=1` emits `WHERE show = 1` → `StatementInvalid` 500. Same class as round-1's `staffing_debt.rb:38`. Drop them (they work via `ransackable_associations`).
- **R2-9** `db/schema.rb:176` (correctness) — `admin_staffing_debts` has no FKs on `user_id`/`show_id`/`admin_staffing_job_id` (and maintenance_debts lacks user/show FKs). An orphaned `user_id` makes required `debt.user` nil → `NoMethodError` in `associate_with_staffing_job`. `dependent: :restrict_with_error` covers the normal path but not direct SQL / legacy data. Add the constraints or document the gap.
- **R2-10** `app/jobs/refresh_fuzzy_both_duplicates_job.rb:16` (efficiency) — `User.all.to_a.group_by { |u| u.last_name&.first&.upcase || 'Z' }` holds the whole table in memory and buckets every blank-last-name user under `'Z'`, then runs `combination(2)` fuzzy matching on that bucket. Exclude blank names and use `find_each`.
- **R2-11** `app/helpers/admin/shared_debt_helper.rb:30` (efficiency) — `debts.where(user: Role.find_by(name: :member).users.ids)` inlines all member ids as an `IN (...)` list per index load; use `where(user_id: …users.select(:id))` (subquery).
- **R2-12** `app/views/admin/dashboard/_staffings_widget.html.erb:11` (efficiency) — 2 COUNT queries per row (`staffing_jobs.count` + `filled_jobs`) × 5 rows = 10 queries; preload and count in Ruby.
- **R2-13** `app/views/admin/dashboard/_opportunities_widget.html.erb:26` (efficiency) — `.count` on an already-materialised relation issues fresh COUNTs; use `.size`.
- **R2-14** `app/controllers/generic_controller.rb:335` (efficiency) — `random_resources.present?` then `random_resources.pluck(:id).sample` loads all ids into Ruby to pick one; use a DB-side random single-row select.

---

## Round 3 additions (2026-07-11)

A third pass over the corners rounds 1-2 didn't reach: `lib/**`, `app/middleware/**`,
`app/inputs/**`, the duplicate-detection/caching models, attachment/ActiveStorage access
control, the remaining public/front controllers, all remaining Stimulus controllers, and
`config/environments`. **These areas are largely clean** — attachment access control is
properly enforced (`authorize!(:show, @attachment)`), the `inputs` and `MalformedRequestHandler`
middleware are sound, and most of `lib/tasks` is one-off `:nocov` import code. 8 new
(mostly low) findings; **no new high-severity issues** — the review is converging.

| # | Severity | Axis | Area | Finding |
|---|----------|------|------|---------|
| R3-1 | Medium | correctness | Controllers | `attachments#file` Content-Disposition omits `filename=` → downloads get the wrong name; and a blob-less attachment `return`s a bare string → MissingTemplate 500 ✓ |
| R3-2 | Medium | correctness | Models | `User#mark_not_duplicate` doesn't invalidate the pair's `CachedDuplicate` row → dismissed duplicate reappears on every reload until the 4am job ✓ |
| R3-3 | Low | security | Middleware | `CloudflareIpSanitizer#from_cloudflare?` uses spoofable `request.ip` (runs before `RemoteIp`) instead of the TCP peer |
| R3-4 | Low | security | Config | `config.hosts` (host authorization) is commented out in `production.rb` → Host-header attacks unmitigated (mailer URLs are pinned, so limited) |
| R3-5 | Low | correctness | Jobs | `RefreshFuzzyBothDuplicatesJob` buckets by surname's first letter, so a typo in that first char (`Smith`/`Zmith`) is never compared (false negative — defeats the bucket's purpose) |
| R3-6 | Low | correctness | lib | `lib/tasks/logic/techie.rb:9` guard uses `Raise(...)` (not a method) and `row.includes(';')` (Array has no `includes`); the semicolon check is also logically wrong |
| R3-7 | Low | correctness | Config | `doorkeeper.rb` declares `resource_owner_authenticator` twice; the first block is silently overridden dead code |
| R3-8 | Low | correctness | Routes | `GET /users/current` routes to a non-existent `UsersController#current` → `ActionNotFound` 404; dead, unreferenced route |

### R3-1. `attachments#file` malformed Content-Disposition + blob-less 500 ✓
**`app/controllers/attachments_controller.rb:23`** (and `:16`) · correctness · Medium

Line 23: `"#{disposition}; #{@attachment.file.filename}"` produces `inline; report.pdf`
instead of `inline; filename="report.pdf"` — browsers ignore the bare token and fall back to
the URL slug when saving, so downloads lose the intended name (value is also unquoted). Line
16: `return "There is no file attached" unless @attachment.file.attached?` returns a bare
string with no `render`, so an attachment whose blob is missing falls through to a
`MissingTemplate` 500. Access control itself is fine (`authorize!(:show, @attachment)`,
line 14). **Fix:** `ActionDispatch::Http::ContentDisposition.format(disposition:, filename:
@attachment.file.filename.to_s)`; render a proper 404/message for the missing-blob case.

### R3-2. `mark_not_duplicate` doesn't invalidate the cache ✓
**`app/models/user.rb:753`** · correctness · Medium

`mark_not_duplicate` only appends to `not_duplicate_user_ids`; it never deletes the matching
`CachedDuplicate` row. `Admin::DuplicatesController#load_cached_duplicates`
(`duplicates_controller.rb:35`) reads `CachedDuplicate` directly and — unlike
`RefreshFuzzyBothDuplicatesJob#check_group` — does **not** filter `marked_not_duplicate?`
pairs. The turbo_stream only removes the row from the current DOM, so after a full reload the
dismissed pair is listed again until the 4am job reruns. The merge/absorb path (`user.rb:681`)
*does* destroy the rows — the invalidation is just inconsistently applied. **Fix:** destroy the
pair's `CachedDuplicate` rows in `mark_not_duplicate` (or filter `marked_not_duplicate?` in
`load_cached_duplicates`).

### R3 low-severity items
- **R3-3** `app/middleware/cloudflare_ip_sanitizer.rb:24` (security) — inserted before `ActionDispatch::RemoteIp` (`application.rb:46`), so `from_cloudflare?`→`request.ip` is computed from attacker-controlled `X-Forwarded-For`/`CLIENT_IP` headers: it trusts a spoofable header to decide whether to distrust a spoofable header. Fails mostly safe (hence low). Use `env['REMOTE_ADDR']` / configure Cloudflare ranges as `trusted_proxies`.
- **R3-4** `config/environments/production.rb:96` (security) — the `config.hosts` block is commented out, so production accepts any `Host` header. The main vector (reset-link poisoning) is blocked because mailer URLs are pinned in `application.rb` and origin-check is on, but any absolute URL built from `request.host` (or Host-keyed cache) is poisonable. Set `config.hosts` with a `/up` exclusion.
- **R3-5** `app/jobs/refresh_fuzzy_both_duplicates_job.rb:16` (correctness) — bucketing on `last_name&.first&.upcase` means a surname whose first character differs (typo/transliteration) is never fuzzy-compared, defeating the "both names fuzzy" bucket. Different axis from R2-10 (cost/memory). Bucket on Soundex/metaphone or compare adjacent buckets.
- **R3-6** `lib/tasks/logic/techie.rb:9` (correctness) — `Raise(ArgumentError, …)` is not a method (→ `NoMethodError`), `row.includes(';')` should be `include?`, and a semicolon-delimited file is a single CSV field so `row` never contains `';'`. Feeding such a file silently proceeds with `child = nil` or crashes with the wrong error.
- **R3-7** `config/initializers/doorkeeper.rb:11` (correctness) — `resource_owner_authenticator` is declared twice; Doorkeeper keeps only the last, so the first block is dead and misleading (a future edit to it would have no effect). Delete the first block.
- **R3-8** `config/routes.rb:45` (correctness) — `get "current", to: "users#current"` targets an action that doesn't exist (UsersController defines only `show`/`consent`); `/users/current` raises `ActionNotFound` (404). Dead, unreferenced route — remove or implement.

---

## Cross-cutting themes

1. **Public attack surface + `html_safe`.** The opportunity submission flow is anonymous, and
   several admin/reviewer views mark its fields `html_safe` (#2). Combined with a permissive
   CSP (#6), stored/reflected XSS is currently exploitable end-to-end. These should be fixed
   together.
2. **Authorization gaps at the framework edges.** `markdown#upload` (#1), `dashboard#widget`
   (#5), the dropzone `access_level` path, and `staffings#sign_up` all sidestep CanCanCan's
   `check_authorization` via `skip_authorization_check` or view-helper checks. A convention of
   "every action either `authorize!`s or explicitly documents why not" would close these.
3. **`create` vs `create!` / non-atomic writes.** #3 and the `find_or_build` TOCTOU (#11) are
   both "the guard exists but the unhappy path still commits/500s." Audit multi-step writes for
   `create!`/`save!` and constraint-race handling.
4. **Duplicated HTTP/retry and modal/dialog logic.** The reimbursements HTTP stack (#4, 429
   bug, `http_transport` reuse) and the JS `<dialog>` controllers each reimplement the same
   behaviour 3× — the divergence is exactly where bugs hide.

## Method notes
- Findings marked **✓ verified** were re-read against source during this review and the failure
  mode confirmed by hand. Verified: #1, #2, #3, #4, #5, #7, #9, #10, #13; R2-1, R2-2, R2-3, R2-4.
- **Review rounds:** Round 1 = models/auth, controllers, services/jobs/mailers, views, JS/config
  (5 domain passes, incl. the 4 high-severity items). Round 2 = data/money layer,
  admin-controller/route/job breadth, quality axes app-wide (3 passes, 14 new, 0 high).
  Round 3 = lib/middleware/inputs, dup-detection/caching, attachment security, remaining public
  controllers + Stimulus + env config (2 passes, 8 new, 0 high). Verified round 3: R3-1, R3-2.
  Each round dedups against this file. **Convergence:** new findings fell from many (incl. 4 high)
  → 14 (0 high, mostly efficiency) → 8 (0 high, mostly low); rounds 2-3 surfaced no new
  high-severity issues and reported the money layer, attachment access control, middleware, and
  inputs as clean. The remaining backlog is low-severity cleanup.
- Nothing was changed. This is a report; each item names its file:line, axis, and a suggested fix.
- No live suite was run (the test DB — `docker start /mysql8` — was not started for this
  read-only pass); the correctness findings are reasoned from source, not reproduced via tests.
</content>
</invoke>
