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
  mode confirmed by hand. Verified: #1, #2, #3, #4, #5, #7, #9, #10, #13.
- Nothing was changed. This is a report; each item names its file:line, axis, and a suggested fix.
- No live suite was run (the test DB — `docker start /mysql8` — was not started for this
  read-only pass); the correctness findings are reasoned from source, not reproduced via tests.
</content>
</invoke>
