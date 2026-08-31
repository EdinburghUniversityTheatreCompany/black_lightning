# Per-cost-centre finance notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each `Reimbursements::CostCentre` its own notification `Role`, so the nightly reminders reach only that centre's admins about only that centre's claims.

**Architecture:** A `notification_role_id` foreign key on `reimbursements_cost_centres` pointing at the legacy-integer-PK `roles` table; a `Reimbursements::NotificationRecipients` PORO as the single recipient-resolution path; and `NightlyBatchJob` reworked to bucket claims by `budget -> cost_centre` and run per centre. An empty role warns loudly instead of going quiet.

**Tech Stack:** Rails 8.1, MySQL (multi-database: `primary` / `queue` / `cache`), Minitest with fixtures, Solid Queue, Tailwind v4, ViewComponent, CanCanCan.

**Spec:** `docs/superpowers/specs/2026-08-31-per-cost-centre-finance-notifications-design.md` — read it alongside this plan.

## Global Constraints

- **`roles` has a legacy INTEGER primary key** (`db/schema.rb`: `create_table "roles", id: :integer`). Every foreign key pointing at it must be `type: :integer`. A default bigint reference aborts the migration with a column-type mismatch.
- **Multi-database app.** `bin/rails db:rollback` aborts with "must run the namespaced task". Use `bin/rails db:rollback:primary STEP=n`.
- **Start the test database first:** `docker start /mysql8`.
- **A dev shell's fnox-exported `REIMBURSEMENTS_*` variables leak real credentials into the suite.** Strip them when running tests by hand: `env -u REIMBURSEMENTS_AZURE_TENANT_ID -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_ALERT_EMAIL -u REIMBURSEMENTS_OPERATOR_EMAIL -u REIMBURSEMENTS_ENABLE_OUTBOUND bin/rails test <path>`. This plan writes that prefix as `$CLEANENV`; define it once per shell:
  ```bash
  CLEANENV='env -u REIMBURSEMENTS_AZURE_TENANT_ID -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_ALERT_EMAIL -u REIMBURSEMENTS_OPERATOR_EMAIL -u REIMBURSEMENTS_ENABLE_OUTBOUND'
  ```
- **No mocking library.** No mocha, no `minitest/mock`. Fake collaborators through the existing `class_attribute` seams (`store_builder`, `graph_builder`, `notifier_builder`, `checker_builder`) and put the previous value back in `teardown`.
- **The production role already exists**: `Fringe Finance Admin`, id 59, already populated. The migration must **find** it and **add no users**.
- **Test and CI databases are schema-loaded, not migrated**, so no data migration ever runs there. Anything tests need must come from fixtures or helpers.
- **Never modify an existing fixture** — with one deliberate exception called out in Task 3, which is unavoidable and requires a full-suite run.
- Run `hk run check` before the final merge; `hk run fix` autofixes what it can.
- Work happens on branch `cost-centre-notifications` in the worktree `.worktrees/cost-centre-notifications`. Run every command from that directory. A background task notification resets the shell's cwd to the main checkout — `cd` back in before any git or test command.

---

## File Structure

| File | Responsibility |
|---|---|
| `db/migrate/20260831120000_add_notification_role_to_reimbursements_cost_centres.rb` | **Create.** Adds the integer FK and points the existing centre at `Fringe Finance Admin`. |
| `app/models/reimbursements/cost_centre.rb` | **Modify.** `belongs_to :notification_role`, the presence validation, and `#notification_role_empty?`. |
| `app/services/reimbursements/notification_recipients.rb` | **Create.** The one place that answers "who gets this centre's operator mail". |
| `app/jobs/reimbursements/nightly_batch_job.rb` | **Modify.** Bucket claims per centre; take recipients from the PORO; warn on an empty role. |
| `app/controllers/admin/reimbursements/settings_controller.rb` | **Modify.** Permit `notification_role_id` on create and update; expose the role list. |
| `app/views/admin/reimbursements/settings/edit.html.erb` | **Modify.** Role picker plus the empty-role hint. |
| `app/views/admin/reimbursements/settings/new.html.erb` | **Modify.** Role picker (a centre cannot be created without one). |
| `app/controllers/admin/reimbursements/status_controller.rb` | **Modify.** Load the finance-permission user ids for the badge. |
| `app/views/admin/reimbursements/status/show.html.erb` | **Modify.** The "Notification recipients" card. |
| `test/support/reimbursements_test_helpers.rb` | **Modify.** `create_reimbursements_cost_centre`, `create_reimbursements_role`, `capture_honeybadger_events`. |
| `test/fixtures/roles.yml` | **Modify (append only).** A `fringe_finance_admin` role fixture. |
| `test/fixtures/reimbursements/cost_centres.yml` | **Modify.** The one unavoidable fixture edit — `fringe` gains its role. |
| `test/services/reimbursements/notification_recipients_test.rb` | **Create.** |
| `test/jobs/reimbursements/nightly_batch_job_test.rb` | **Modify.** Recipients now come from the role; new per-centre cases. |
| `test/models/reimbursements/cost_centre_test.rb` | **Modify.** Validation + `notification_role_empty?`. |
| `test/functional/admin/reimbursements/settings_controller_test.rb` | **Modify.** Setting the role. |
| `test/functional/admin/reimbursements/status_controller_test.rb` | **Modify.** The badges. |
| `CLAUDE.md` | **Modify.** Record the traps, per the project's documentation convention. |

---

### Task 1: The migration and the association

Adds the column and points production's existing cost centre at its existing role. No validation yet — that lands in Task 4, after the test suite can satisfy it.

**Files:**
- Create: `db/migrate/20260831120000_add_notification_role_to_reimbursements_cost_centres.rb`
- Modify: `app/models/reimbursements/cost_centre.rb`
- Test: `test/models/reimbursements/cost_centre_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Reimbursements::CostCentre#notification_role` -> `Role` or `nil`; `#notification_role_id` -> `Integer` or `nil`; `#notification_role_empty?` -> `true` when there is no role or the role has no users.

- [ ] **Step 1: Write the migration**

Create `db/migrate/20260831120000_add_notification_role_to_reimbursements_cost_centres.rb`:

```ruby
class AddNotificationRoleToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Who gets this cost centre's operator reminders (the nightly's stale-pending
  # and ready-to-batch emails).
  #
  # Until now there was one global list: every user holding the
  # `manage`/`reimbursements_finance` grid permission. That is fine while Fringe
  # (F40) is the only live centre and wrong the moment termtime (BED) joins it,
  # because every Fringe admin would get termtime's reminders and vice versa.
  #
  # A Role rather than a join table or an address column: roles are the
  # committee-membership machinery this society already runs on, so a handover is
  # the same gesture as every other handover, and the members are real accounts
  # that cannot rot into someone who has left. These finance roles are
  # deliberately NOT part of the annual Role#archive sweep.
  #
  # roles.id is a legacy INTEGER primary key, not a bigint. A default bigint
  # reference aborts this migration with a column-type mismatch.
  def up
    add_reference :reimbursements_cost_centres, :notification_role,
                  type: :integer, index: true, foreign_key: { to_table: :roles }

    # Production already has this role (id 59) with its members chosen by hand,
    # so find it rather than seeding it, and add NOBODY to it -- inventing
    # members from the permission grid would email people who were not chosen.
    # On a developer's migrated database the name does not exist yet, so it is
    # created empty; that centre then trips the empty-role warning until someone
    # fills it in, which is the intended signal rather than a silent default.
    role = Role.find_or_create_by!(name: "Fringe Finance Admin")

    # update_columns, not update!: the new model code carrying the presence
    # validation is already loaded by the time this migration runs.
    Reimbursements::CostCentre.where(notification_role_id: nil).find_each do |cost_centre|
      cost_centre.update_columns(notification_role_id: role.id)
    end
  end

  def down
    remove_reference :reimbursements_cost_centres, :notification_role,
                     foreign_key: { to_table: :roles }
  end
end
```

- [ ] **Step 2: Run the migration and verify it rolls back**

```bash
docker start /mysql8
bin/rails db:migrate
bin/rails db:rollback:primary STEP=1
bin/rails db:migrate
```

Expected: all three succeed. `db:rollback:primary` is required — a bare `db:rollback` aborts with "you must run the namespaced task". `db/schema.rb` should now show `t.integer "notification_role_id"` on `reimbursements_cost_centres` with its index and FK.

- [ ] **Step 3: Write the failing model test**

Append to `test/models/reimbursements/cost_centre_test.rb`, inside the existing test class:

```ruby
test "notification_role_empty? is true with no role at all" do
  centre = CostCentre.new(key: "nr1", name: "NR One", eusa_code: "NR1",
                          receive_mailbox: "a@b.co", send_mailbox: "a@b.co")

  assert_predicate centre, :notification_role_empty?
end

test "notification_role_empty? is true for a role with no users" do
  centre = CostCentre.new(key: "nr2", name: "NR Two", eusa_code: "NR2",
                          receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                          notification_role: Role.create!(name: "NR Two Finance Admin"))

  assert_predicate centre, :notification_role_empty?
end

test "notification_role_empty? is false once the role has a member" do
  role = Role.create!(name: "NR Three Finance Admin")
  role.users << users(:member)
  centre = CostCentre.new(key: "nr3", name: "NR Three", eusa_code: "NR3",
                          receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                          notification_role: role)

  assert_not_predicate centre, :notification_role_empty?
end
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
$CLEANENV bin/rails test test/models/reimbursements/cost_centre_test.rb -n "/notification_role_empty/"
```

Expected: FAIL with `NoMethodError: undefined method 'notification_role_empty?'` (and `unknown attribute 'notification_role'` if the association is missing).

- [ ] **Step 5: Add the association and the predicate**

In `app/models/reimbursements/cost_centre.rb`, add the association immediately after the `serialize :nightly_run_days, coder: JSON` line:

```ruby
    # Who gets this centre's operator reminders. A Role, so a committee handover
    # is the same gesture as every other handover and the members are real
    # accounts. Optional at the database level for now; Task 4 adds the presence
    # validation once every test can satisfy it.
    belongs_to :notification_role, class_name: "Role", optional: true
```

and this predicate in the public section, just above `# --- Copy derived from this cost centre ---`:

```ruby
    # No role, or a role nobody is in -- either way this centre's reminders
    # would reach nobody. The nightly warns on it rather than going quiet, and
    # the Integration Status page badges it.
    def notification_role_empty?
      notification_role.nil? || notification_role.users.empty?
    end
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
$CLEANENV bin/rails test test/models/reimbursements/cost_centre_test.rb
```

Expected: PASS, whole file green.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260831120000_add_notification_role_to_reimbursements_cost_centres.rb db/schema.rb app/models/reimbursements/cost_centre.rb test/models/reimbursements/cost_centre_test.rb
git commit -m "feat(reimbursements): give a cost centre a notification role"
```

---

### Task 2: `NotificationRecipients`

The single answer to "who gets this centre's operator mail", replacing `NightlyBatchJob#compute_operator_emails`.

**Files:**
- Create: `app/services/reimbursements/notification_recipients.rb`
- Test: `test/services/reimbursements/notification_recipients_test.rb`

**Interfaces:**
- Consumes: `CostCentre#notification_role` from Task 1.
- Produces: `Reimbursements::NotificationRecipients.for(cost_centre)` -> `Array<String>` of email addresses, possibly empty. Never `nil`.

- [ ] **Step 1: Write the failing test**

Create `test/services/reimbursements/notification_recipients_test.rb`:

```ruby
require "test_helper"

module Reimbursements
  class NotificationRecipientsTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def centre_with(role)
      CostCentre.new(key: "nrt", name: "NRT", eusa_code: "NRT",
                     receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                     notification_role: role)
    end

    test "returns the notification role's members' emails" do
      role = Role.create!(name: "NRT Finance Admin")
      role.users << users(:member)

      assert_equal [ users(:member).email ], NotificationRecipients.for(centre_with(role))
    end

    test "returns an empty array for a role with no members" do
      assert_empty NotificationRecipients.for(centre_with(Role.create!(name: "NRT Empty")))
    end

    test "returns an empty array when no role is set" do
      assert_empty NotificationRecipients.for(centre_with(nil))
    end

    test "returns an empty array for a nil cost centre" do
      assert_empty NotificationRecipients.for(nil)
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the role entirely" do
      role = Role.create!(name: "NRT Overridden")
      role.users << users(:member)

      with_env("REIMBURSEMENTS_OPERATOR_EMAIL" => "ops@example.com") do
        assert_equal [ "ops@example.com" ], NotificationRecipients.for(centre_with(role))
      end
    end

    test "the override applies even when the centre has no role" do
      with_env("REIMBURSEMENTS_OPERATOR_EMAIL" => "ops@example.com") do
        assert_equal [ "ops@example.com" ], NotificationRecipients.for(centre_with(nil))
      end
    end

    test "drops blank emails and de-duplicates" do
      role = Role.create!(name: "NRT Dupes")
      role.users << users(:member)
      role.users << users(:member)

      assert_equal [ users(:member).email ], NotificationRecipients.for(centre_with(role))
    end

    private

    def with_env(pairs)
      original = pairs.transform_values { |_| nil }.merge(pairs.keys.index_with { |k| ENV[k] })
      pairs.each { |key, value| ENV[key] = value }
      yield
    ensure
      original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
$CLEANENV bin/rails test test/services/reimbursements/notification_recipients_test.rb
```

Expected: FAIL with `NameError: uninitialized constant Reimbursements::NotificationRecipients`.

- [ ] **Step 3: Write the implementation**

Create `app/services/reimbursements/notification_recipients.rb`:

```ruby
module Reimbursements
  ##
  # Who gets a cost centre's OPERATOR mail -- the nightly's stale-pending and
  # ready-to-batch reminders, and its failure alert. One definition, so the job
  # and any later caller cannot drift apart on it.
  #
  # This replaced a global list: every user in every role holding the
  # `manage`/`reimbursements_finance` grid permission. That list is still what
  # gates the finance SCREENS -- a Fringe admin can still open a termtime claim.
  # It is only who gets TOLD that is now per centre.
  #
  # REIMBURSEMENTS_OPERATOR_EMAIL stays whole-portal and wins outright: it is the
  # "divert everything to one inbox" switch, so scoping it per centre would
  # defeat the only thing it exists for.
  module NotificationRecipients
    def self.for(cost_centre)
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override

      role = cost_centre&.notification_role
      return [] if role.nil?

      role.users.map(&:email).compact_blank.uniq
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
$CLEANENV bin/rails test test/services/reimbursements/notification_recipients_test.rb
```

Expected: PASS, 7 assertions' worth of tests green.

- [ ] **Step 5: Commit**

```bash
git add app/services/reimbursements/notification_recipients.rb test/services/reimbursements/notification_recipients_test.rb
git commit -m "feat(reimbursements): resolve operator recipients per cost centre"
```

---

### Task 3: Test groundwork for the presence validation

The validation in Task 4 would break 35 inline `CostCentre.create!` / `.new` sites across 9 test files. This task removes that duplication first, so Task 4 is a two-line change rather than a 35-site sweep.

**Files:**
- Modify: `test/support/reimbursements_test_helpers.rb`
- Modify: `test/fixtures/roles.yml` (append only)
- Modify: `test/fixtures/reimbursements/cost_centres.yml`
- Modify (mechanical sweep): `test/functional/admin/reimbursements/reconcile_controller_test.rb`, `test/jobs/reimbursements/mailbox_poll_job_test.rb`, `test/jobs/reimbursements/nightly_batch_job_test.rb`, `test/models/reimbursements/budget_import_test.rb`, `test/models/reimbursements/cost_centre_test.rb`, `test/services/reimbursements/actuals_attribution_test.rb`, `test/services/reimbursements/batch_processor_test.rb`, `test/services/reimbursements/eusa_email_composer_test.rb`, `test/services/reimbursements/notifier_test.rb`

**Interfaces:**
- Consumes: `CostCentre#notification_role` from Task 1.
- Produces:
  - `create_reimbursements_role(name:, users: [])` -> `Role`
  - `create_reimbursements_cost_centre(key:, name:, eusa_code:, receive_mailbox:, send_mailbox:, notification_role: :auto, notification_users: [], **attrs)` -> `Reimbursements::CostCentre`. `notification_role: :auto` builds an empty role named `"#{name} Finance Admin"`; pass `nil` explicitly to leave the centre without one; pass a `Role` to use it.
  - `capture_honeybadger_events { ... }` -> `Array<[String, Hash]>` of `Honeybadger.event` calls.
  - Fixture `roles(:fringe_finance_admin)`, referenced by `cost_centres(:fringe)`.

**Note on the fixture edit.** `rails-core` rule 1 says never modify an existing fixture. This is the one unavoidable exception: fixtures load by raw insert and skip validations, so `cost_centres(:fringe)` would load fine but raise on any later `update!` — including `record_nightly_run!`, which the nightly test calls. The rule's own reason (rule 8) applies: run the **full** suite before merging.

- [ ] **Step 1: Add the role fixture**

Append to `test/fixtures/roles.yml`. **No explicit `id:`** — an explicit id would not match `ActiveRecord::FixtureSet.identify(:fringe_finance_admin)`, so the label reference from `cost_centres.yml` would point at a different row and `notification_role` would come back `nil`:

```yaml
# The cost centre's notification recipients (Reimbursements::CostCentre
# #notification_role). Deliberately has no explicit id: cost_centres.yml
# references it by label, which resolves through FixtureSet.identify, and an
# explicit id would not match that hash.
fringe_finance_admin:
  name: "Fringe Finance Admin"
```

- [ ] **Step 2: Point the cost centre fixture at it**

Edit `test/fixtures/reimbursements/cost_centres.yml` so `fringe` reads:

```yaml
# Reimbursements::CostCentre fixtures. Rails infers the class from the
# reimbursements/ path -> reimbursements_cost_centres table.
#
# notification_role is required on the model: without it every update! on this
# row (record_nightly_run! included) would raise. The role is deliberately EMPTY
# -- a test that wants recipients adds users to roles(:fringe_finance_admin)
# itself, so no test inherits an operator mailing list it did not ask for.
fringe:
  key: fringe
  name: Bedlam Fringe 2026
  eusa_code: F40
  receive_mailbox: reimbursements@bedlamfringe.co.uk
  send_mailbox: reimbursements@bedlamfringe.co.uk
  notification_role: fringe_finance_admin
```

- [ ] **Step 3: Add the helpers**

In `test/support/reimbursements_test_helpers.rb`, add to the "Database seed helpers" section, immediately after `create_reimbursements_person`:

```ruby
  # A notification role for a cost centre. Roles are global (not namespaced), so
  # give each one a distinct name or the uniqueness of the fixture roles bites.
  def create_reimbursements_role(name:, users: [])
    role = Role.create!(name: name)
    Array(users).each { |user| role.users << user }
    role
  end

  # A cost centre with a notification role attached, since the model requires
  # one. `notification_role: :auto` (the default) builds an EMPTY role, which is
  # what almost every test wants -- it satisfies the validation without silently
  # giving the test an operator mailing list. Pass `nil` to build a centre with
  # no role (for the empty-role paths), or a Role to share one.
  def create_reimbursements_cost_centre(key:, name:, eusa_code:,
                                        receive_mailbox: "in@example.com",
                                        send_mailbox: "out@example.com",
                                        notification_role: :auto,
                                        notification_users: [], **attrs)
    role =
      if notification_role == :auto
        create_reimbursements_role(name: "#{name} Finance Admin", users: notification_users)
      else
        notification_role
      end

    Reimbursements::CostCentre.create!(key: key, name: name, eusa_code: eusa_code,
                                       receive_mailbox: receive_mailbox,
                                       send_mailbox: send_mailbox,
                                       notification_role: role, **attrs)
  end
```

- [ ] **Step 4: Add the Honeybadger event capture helper**

In `test/support/honeybadger_test_helpers.rb`, add alongside `capture_honeybadger_notices`:

```ruby
  # Honeybadger.event, as capture_honeybadger_notices does for Honeybadger.notify.
  # The nightly reports an empty notification role as an event, not an error --
  # it is a configuration gap, not an exception.
  def capture_honeybadger_events
    events = []
    original = Honeybadger.method(:event)
    Honeybadger.define_singleton_method(:event) { |name, **payload| events << [ name, payload ] }
    yield
    events
  ensure
    Honeybadger.define_singleton_method(:event, original)
  end
```

- [ ] **Step 5: Sweep the inline creation sites**

Find them:

```bash
grep -rn "CostCentre.create!" test/
```

Replace every one with `create_reimbursements_cost_centre(...)`, keeping the same keyword arguments. Example — `test/services/reimbursements/actuals_attribution_test.rb:10`:

```ruby
# before
@termtime = CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
                               receive_mailbox: "bed@example.com",
                               send_mailbox: "bed@example.com")
# after
@termtime = create_reimbursements_cost_centre(key: "termtime", name: "Bedlam Termtime",
                                              eusa_code: "BED",
                                              receive_mailbox: "bed@example.com",
                                              send_mailbox: "bed@example.com")
```

Two things to check as you go:

1. **The test class must `include ReimbursementsTestHelpers`.** Add it if missing.
2. **`CostCentre.new` sites in `test/models/reimbursements/cost_centre_test.rb` that assert a validation failure must stay `CostCentre.new`** — they are testing the model's own validations and must not be routed through a helper that fills fields in. Give each one an explicit `notification_role:` so it fails on the attribute it is actually testing, not on the missing role. The three `notification_role_empty?` tests added in Task 1 already do this correctly and need no change.

- [ ] **Step 6: Run the affected files**

```bash
$CLEANENV bin/rails test test/models/reimbursements/cost_centre_test.rb test/models/reimbursements/budget_import_test.rb test/services/reimbursements/actuals_attribution_test.rb test/services/reimbursements/batch_processor_test.rb test/services/reimbursements/eusa_email_composer_test.rb test/services/reimbursements/notifier_test.rb test/jobs/reimbursements/mailbox_poll_job_test.rb test/jobs/reimbursements/nightly_batch_job_test.rb test/functional/admin/reimbursements/reconcile_controller_test.rb
```

Expected: PASS. Nothing behavioural changed yet — the helper produces the same rows plus a role.

- [ ] **Step 7: Commit**

```bash
git add test/support/reimbursements_test_helpers.rb test/support/honeybadger_test_helpers.rb test/fixtures/roles.yml test/fixtures/reimbursements/cost_centres.yml test/
git commit -m "test(reimbursements): build cost centres through a helper that attaches a role"
```

---

### Task 4: Require the role, and collect it in the UI

**Files:**
- Modify: `app/models/reimbursements/cost_centre.rb`
- Modify: `app/controllers/admin/reimbursements/settings_controller.rb`
- Modify: `app/views/admin/reimbursements/settings/edit.html.erb`
- Modify: `app/views/admin/reimbursements/settings/new.html.erb`
- Test: `test/models/reimbursements/cost_centre_test.rb`, `test/functional/admin/reimbursements/settings_controller_test.rb`

**Interfaces:**
- Consumes: `create_reimbursements_cost_centre` (Task 3), `CostCentre#notification_role_empty?` (Task 1).
- Produces: `CostCentre` is invalid without `notification_role`; `SettingsController` permits `:notification_role_id` on both create and update, and exposes `selectable_roles` as a helper method returning `Role.order(:name)`.

- [ ] **Step 1: Write the failing model test**

Append to `test/models/reimbursements/cost_centre_test.rb`:

```ruby
test "is invalid without a notification role" do
  centre = CostCentre.new(key: "norole", name: "No Role", eusa_code: "NR9",
                          receive_mailbox: "a@b.co", send_mailbox: "a@b.co")

  assert_not centre.valid?
  assert centre.errors[:notification_role].present?
end

test "is valid with a notification role, even an empty one" do
  centre = CostCentre.new(key: "hasrole", name: "Has Role", eusa_code: "HR9",
                          receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                          notification_role: Role.create!(name: "Has Role Finance Admin"))

  assert_predicate centre, :valid?
end
```

Note: assert on `errors[:notification_role].present?`, never on Rails' default "can't be blank" string — this app's validation messages are i18n-customised.

- [ ] **Step 2: Run it to verify it fails**

```bash
$CLEANENV bin/rails test test/models/reimbursements/cost_centre_test.rb -n "/notification role/"
```

Expected: FAIL — `centre.valid?` returns `true`, so `assert_not` fails.

- [ ] **Step 3: Add the validation**

In `app/models/reimbursements/cost_centre.rb`, replace the comment on the association added in Task 1 (its second paragraph is now out of date) so it reads:

```ruby
    # Who gets this centre's operator reminders. A Role, so a committee handover
    # is the same gesture as every other handover and the members are real
    # accounts. Required -- a cost centre whose reminders reach nobody leaves a
    # producer waiting indefinitely with nothing on screen to explain it.
    #
    # `optional: true` stays on the association deliberately: the requirement is
    # the explicit validation below, so the error hangs off :notification_role
    # (the attribute the form labels) rather than off belongs_to's own message.
    belongs_to :notification_role, class_name: "Role", optional: true
```

and add the validation beside the other `validates` calls, after `validates :name, :eusa_code, :receive_mailbox, :send_mailbox, presence: true`:

```ruby
    validates :notification_role, presence: true
```

- [ ] **Step 4: Run it to verify it passes**

```bash
$CLEANENV bin/rails test test/models/reimbursements/cost_centre_test.rb
```

Expected: PASS, whole file green.

- [ ] **Step 5: Write the failing controller test**

Append to `test/functional/admin/reimbursements/settings_controller_test.rb`, following the file's existing sign-in and permission setup:

```ruby
test "updating a cost centre sets its notification role" do
  role = Role.create!(name: "Termtime Finance Admin")

  patch :update, params: { key: ::Reimbursements::CostCentre.default.key,
                           cost_centre: { notification_role_id: role.id } }

  assert_equal role, ::Reimbursements::CostCentre.default.reload.notification_role
end

test "creating a cost centre requires a notification role" do
  role = Role.create!(name: "Brand New Finance Admin")

  assert_difference -> { ::Reimbursements::CostCentre.count }, 1 do
    post :create, params: { cost_centre: { name: "Brand New", eusa_code: "BN1",
                                           receive_mailbox: "bn@example.com",
                                           send_mailbox: "bn@example.com",
                                           notification_role_id: role.id } }
  end

  assert_equal role, ::Reimbursements::CostCentre.find_by(eusa_code: "BN1").notification_role
end

test "creating a cost centre without a notification role re-renders with an error" do
  assert_no_difference -> { ::Reimbursements::CostCentre.count } do
    post :create, params: { cost_centre: { name: "Roleless", eusa_code: "RL1",
                                           receive_mailbox: "rl@example.com",
                                           send_mailbox: "rl@example.com" } }
  end

  assert_response :unprocessable_entity
end
```

- [ ] **Step 6: Run it to verify it fails**

```bash
$CLEANENV bin/rails test test/functional/admin/reimbursements/settings_controller_test.rb -n "/notification role/"
```

Expected: FAIL — `notification_role_id` is not permitted, so it is dropped and the role stays `nil`.

- [ ] **Step 7: Permit the parameter and expose the role list**

In `app/controllers/admin/reimbursements/settings_controller.rb`:

Add `:notification_role_id` to both parameter methods:

```ruby
      def create_params
        params.require(:cost_centre).permit(
          :key, :name, :eusa_code, :receive_mailbox, :send_mailbox, :notification_role_id
        )
      end

      def settings_params
        permitted = params.require(:cost_centre).permit(
          :receive_mailbox, :send_mailbox, :eusa_recipient, :eusa_signature_name,
          :sharepoint_site_url, :notification_role_id
        )
        permitted[:nightly_run_days] = normalized_run_days
        permitted
      end
```

and expose the picker's options, next to the other private helpers:

```ruby
      helper_method :selectable_roles

      # Every role, for the notification-role picker. Not filtered to
      # finance-permission holders: the permission grid and the notification list
      # are deliberately separate, and a mismatch is surfaced as a badge on the
      # Integration Status page rather than hidden by removing the option.
      def selectable_roles
        @selectable_roles ||= Role.order(:name).to_a
      end
```

(`helper_method` goes at the top of the class with the existing macros, not inside `private`.)

- [ ] **Step 8: Add the picker to the edit form**

In `app/views/admin/reimbursements/settings/edit.html.erb`, immediately after the closing `</div>` of the receive/send mailbox row and before the `<p class="text-xs text-gray-500 -mt-2">` mailbox hint, insert:

```erb
    <div>
      <%= f.label :notification_role_id, "Notification recipients (role)", class: "block text-sm font-medium" %>
      <%= f.collection_select :notification_role_id, selectable_roles, :id, :name,
                              { include_blank: "Select a role" },
                              class: "simple-select2 border border-gray-300 rounded px-2 py-1 text-sm w-72",
                              "aria-describedby": "notification_role_hint" %>
      <p id="notification_role_hint" class="text-xs text-gray-500 mt-1">
        Everyone in this role gets this cost centre's nightly reminders — claims stuck awaiting
        approval, and the queue ready to batch. Nobody outside it does.
      </p>
      <% if @cost_centre.notification_role_empty? %>
        <p class="text-xs text-red-700 mt-1">
          <strong>This role has no members</strong>, so nobody will get this cost centre's reminders.
          Add people to it under Settings → Roles.
        </p>
      <% end %>
    </div>
```

- [ ] **Step 9: Add the picker to the new form**

In `app/views/admin/reimbursements/settings/new.html.erb`, add the same field (without the `notification_role_empty?` block — a brand-new record has nothing to report yet), alongside the other required fields:

```erb
    <div>
      <%= f.label :notification_role_id, "Notification recipients (role)", class: "block text-sm font-medium" %>
      <%= f.collection_select :notification_role_id, selectable_roles, :id, :name,
                              { include_blank: "Select a role" },
                              class: "simple-select2 border border-gray-300 rounded px-2 py-1 text-sm w-72",
                              "aria-describedby": "new_notification_role_hint" %>
      <p id="new_notification_role_hint" class="text-xs text-gray-500 mt-1">
        Everyone in this role gets this cost centre's nightly reminders. Required — a cost centre
        whose reminders reach nobody leaves producers waiting with nothing on screen to explain it.
      </p>
    </div>
```

- [ ] **Step 10: Run the controller tests**

```bash
$CLEANENV bin/rails test test/functional/admin/reimbursements/settings_controller_test.rb
```

Expected: PASS, whole file green. If the "without a notification role" case returns `200` rather than `422`, check how `#create` renders its failure — match whatever status the existing create-failure path uses and adjust the assertion to it rather than changing the controller.

**Why these are request-level, not browser tests:** `select_controller.js` replaces every `.simple-select2` element with a Tom Select widget and hides the original `<select>`, so Capybara's `select "X", from: "Label"` raises `ElementNotFound`. Driving it needs the `tom_select` click helper from `test/system/admin/reimbursements/producer_js_test.rb`. The parameter plumbing is what matters here, so cover it with `post`/`patch` as above.

- [ ] **Step 11: Commit**

```bash
git add app/models/reimbursements/cost_centre.rb app/controllers/admin/reimbursements/settings_controller.rb app/views/admin/reimbursements/settings/edit.html.erb app/views/admin/reimbursements/settings/new.html.erb test/models/reimbursements/cost_centre_test.rb test/functional/admin/reimbursements/settings_controller_test.rb
git commit -m "feat(reimbursements): require a notification role and collect it in Settings"
```

---

### Task 5: Scope the nightly per cost centre

The core of the change. Removes the `TODO(mysql)` hard skip, buckets claims by `budget -> cost_centre`, and takes recipients per centre.

**Files:**
- Modify: `app/jobs/reimbursements/nightly_batch_job.rb`
- Test: `test/jobs/reimbursements/nightly_batch_job_test.rb`

**Interfaces:**
- Consumes: `NotificationRecipients.for(cost_centre)` (Task 2), `create_reimbursements_cost_centre` and `capture_honeybadger_events` (Task 3).
- Produces: no new public interface. `NightlyBatchJob.perform_now(dry_run:, today:)` keeps its signature; `compute_operator_emails` and `operator_emails` are removed.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/reimbursements/nightly_batch_job_test.rb`. Also update the existing `setup` block: recipients now come from the role, so replace

```ruby
      # Operator recipients: a user holding the finance permission.
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
```

with

```ruby
      # Operator recipients come from the cost centre's notification role, not
      # from the finance permission grid. The fixture role is empty on purpose,
      # so every test that expects mail to go out says so here.
      roles(:fringe_finance_admin).users << users(:member)
```

Then add these tests:

```ruby
    # --- Per-cost-centre scoping ------------------------------------------

    test "each due cost centre is reminded about only its own claims" do
      termtime = create_reimbursements_cost_centre(
        key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "in@termtime.co.uk", send_mailbox: "send@termtime.co.uk",
        notification_users: [ users(:committee) ], nightly_run_days: [ 4 ]
      )
      termtime_budget = create_reimbursements_budget(name: "Termtime props")
      termtime_budget.update!(cost_centre: termtime)
      CostCentre.default.update!(notification_role: roles(:fringe_finance_admin))
      budget.update!(cost_centre: CostCentre.default)

      fringe_claim = approved_expense
      termtime_claim = create_reimbursements_expense(person: payee, budget: termtime_budget,
                                                     status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready)
      assert_equal 2, ready.size

      by_recipient = ready.to_h { |(_name, kwargs)| [ kwargs[:recipients].sort, kwargs[:expenses] ] }
      fringe_rows = by_recipient.fetch([ users(:member).email ])
      termtime_rows = by_recipient.fetch([ users(:committee).email ])

      assert_equal [ fringe_claim.auto_number ], fringe_rows.map { |row| row[:auto_number] }
      assert_equal [ termtime_claim.auto_number ], termtime_rows.map { |row| row[:auto_number] }
    end

    test "a claim whose budget has no cost centre falls to the default centre" do
      budget.update!(cost_centre: nil)
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ users(:member).email ], ready[:recipients]
      assert_equal 1, ready[:expenses].size
    end

    test "a non-default cost centre reports on its own run-day" do
      termtime = create_reimbursements_cost_centre(
        key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "in@termtime.co.uk", send_mailbox: "send@termtime.co.uk",
        notification_users: [ users(:committee) ], nightly_run_days: [ 4 ]
      )
      # The default centre is NOT due today, so the old skip_unscoped_cost_centre
      # guard would have silenced termtime entirely.
      CostCentre.default.update!(nightly_run_days: [ 1 ])
      termtime_budget = create_reimbursements_budget(name: "Termtime props")
      termtime_budget.update!(cost_centre: termtime)
      create_reimbursements_expense(person: payee, budget: termtime_budget, status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ users(:committee).email ], ready[:recipients]
      assert_equal THURSDAY, termtime.reload.last_nightly_run_on
    end

    # --- Empty notification role ------------------------------------------

    test "an empty notification role sends nothing and does not record the run" do
      roles(:fringe_finance_admin).users.clear
      approved_expense

      events = capture_honeybadger_events do
        NightlyBatchJob.perform_now(today: THURSDAY)
      end

      assert_empty @notifier.calls
      assert_nil CostCentre.default.reload.last_nightly_run_on
      assert_includes events.map(&:first), "reimbursements.nightly_no_recipients"
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL still overrides the role" do
      roles(:fringe_finance_admin).users.clear
      approved_expense
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "ops@example.com"

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "ops@example.com" ], mailer_calls(:approved_ready).sole.last[:recipients]
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end
```

Then **delete** the existing test at `test/jobs/reimbursements/nightly_batch_job_test.rb:166` that asserts a second cost centre is skipped — that behaviour is exactly what this task removes. Read it first; if it also asserts something still true (that the default centre's reminder is unaffected), keep that half as its own test.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
$CLEANENV bin/rails test test/jobs/reimbursements/nightly_batch_job_test.rb
```

Expected: FAIL — the new per-centre tests fail because `deliver_reminders` still returns `skip_unscoped_cost_centre` for anything but the default centre, and recipients still come from the permission grid.

- [ ] **Step 3: Rework the job**

In `app/jobs/reimbursements/nightly_batch_job.rb`:

Replace `#perform` and `#run_for`, and delete `#skip_unscoped_cost_centre`, `#default_cost_centre`, `#operator_emails` and `#compute_operator_emails` entirely:

```ruby
    def perform(dry_run: false, today: Date.current)
      CostCentre.all.each { |cost_centre| run_for(cost_centre, dry_run: dry_run, today: today) }
    end

    private

    # Recipients are resolved BEFORE anything is built, so an empty notification
    # role is reported as the configuration gap it is rather than discovered
    # halfway through. Crucially the run-day is NOT recorded in that case: the
    # old code returned "delivered" for no recipients, which marked the day
    # handled forever and lost the alert. Leaving it unrecorded means tomorrow's
    # run tries again and keeps alarming until somebody fills the role in.
    def run_for(cost_centre, dry_run:, today:)
      unless cost_centre.nightly_due?(today)
        Rails.logger.info("Nightly: #{cost_centre.key} not due on #{today} — skipping")
        return
      end

      recipients = NotificationRecipients.for(cost_centre)
      return warn_no_recipients(cost_centre) if recipients.empty?

      delivered = deliver_reminders(cost_centre, recipients, dry_run: dry_run, today: today)
      record_run(cost_centre, today) if delivered && !dry_run
    rescue StandardError => e
      handle_failure(cost_centre, recipients, e, today, dry_run)
    end

    def warn_no_recipients(cost_centre)
      Rails.logger.warn("Nightly: #{cost_centre.key} has no notification recipients — " \
                        "its reminders went nowhere. Add people to the " \
                        "#{cost_centre.notification_role&.name.inspect} role.")
      Honeybadger.event("reimbursements.nightly_no_recipients",
                        cost_centre: cost_centre.key,
                        notification_role: cost_centre.notification_role&.name)
      nil
    end
```

Replace `#deliver_reminders` (dropping the `TODO(mysql)` comment and the default-centre guard with it):

```ruby
    # Both reminders must be ATTEMPTED even when the first fails to send. The
    # array literal is what enforces that: `a && b` would short-circuit and
    # silently drop the approved reminder whenever Graph fluffed the pending
    # one, so don't rewrite this into a boolean expression.
    def deliver_reminders(cost_centre, recipients, dry_run:, today:)
      claims = claims_for(cost_centre)
      [ remind_stale_pending(cost_centre, recipients, claims.select(&:pending?),
                             today: today, dry_run: dry_run),
        remind_approved(cost_centre, recipients, claims.select(&:approved?),
                        today: today, dry_run: dry_run) ].all?
    end
```

Add the bucketing, next to the other helpers:

```ruby
    # --- Which claims belong to which cost centre --------------------------
    # An expense carries no cost-centre column; it resolves one through its
    # budget. store.expenses already `includes(:budget)`, so this costs no extra
    # query however many centres there are -- and it is memoized, so the whole
    # job reads the ledger once rather than once per centre.

    def claims_for(cost_centre)
      claims_by_cost_centre_id.fetch(cost_centre.id, [])
    end

    # A claim whose budget names no cost centre falls to the DEFAULT centre
    # rather than to nobody. Same leniency as DatabaseStore#in_year (a row with
    # no financial year belongs to the year being viewed) and the reconcile
    # matcher (a budget with no cost centre still matches). The asymmetry that
    # governs it: a claim reminded to the wrong centre's admins is visible and
    # correctable, whereas a claim reminded to nobody leaves a producer waiting
    # indefinitely with nothing on screen to explain it. Prefer the wrong
    # reminder over silence.
    #
    # NOT memoized with ||=: the store read can raise (that is what drives
    # handle_failure), and a rescued raise must not be cached as an empty
    # result for the centres that follow.
    def claims_by_cost_centre_id
      return @claims_by_cost_centre_id if defined?(@claims_by_cost_centre_id)

      default_id = CostCentre.default&.id
      @claims_by_cost_centre_id =
        store.expenses.group_by { |expense| expense.budget&.cost_centre_id || default_id }
    end
```

Change the two reminder methods to take `recipients` and pass them straight to `notify`:

```ruby
    def remind_stale_pending(cost_centre, recipients, pending, today:, dry_run:)
```
```ruby
      notify(cost_centre, recipients) do |emailer, to|
        emailer.pending_reminder(recipients: to, rows: rows, run_date: run_date(today),
                                 threshold_days: PENDING_REMINDER_DAYS)
      end
```
```ruby
    def remind_approved(cost_centre, recipients, approved, today:, dry_run:)
```
```ruby
      notify(cost_centre, recipients) do |emailer, to|
        emailer.approved_ready(recipients: to, expenses: rows, total: format("%.2f", total),
                               run_date: run_date(today),
                               next_run_day: next_run_day(cost_centre, today))
      end
```

Replace `#notify` (the empty-recipients branch is gone — `run_for` handles it up front):

```ruby
    # Send an operator alert through Graph from the cost centre's send mailbox.
    # A Graph failure must never break the nightly run (or trip the surrounding
    # rescue into sending a spurious failure email), so it's rescued + logged.
    #
    # Returns true when the alert was sent, false when a send was attempted and
    # failed. run_for gates record_run on EVERY reminder returning true:
    # recording a run whose alert silently failed would lose that alert forever,
    # since nightly_due? would then treat the run-day as already handled. The
    # cost is that a run where one reminder sent and the other failed re-sends
    # the first one tomorrow -- the right trade, since these alerts are
    # deliberately at-least-once.
    def notify(cost_centre, recipients)
      yield(notifier(cost_centre), recipients)
      true
    rescue GraphAuth::AuthError => e
      Rails.logger.error("Nightly: Graph authentication failing for #{cost_centre.key} — #{e.message}")
      GraphAuthAlert.notify(e, source: "reimbursements_nightly_batch")
      false
    rescue StandardError => e
      log_and_notify("Nightly: operator email failed for #{cost_centre.key} — #{e.message}", e,
                     context: { source: "reimbursements_nightly_email", cost_centre: cost_centre.key })
      false
    end
```

And `#handle_failure`, which now takes the recipients it was given (they can be `nil` if the raise happened before they resolved):

```ruby
    def handle_failure(cost_centre, recipients, error, today, dry_run)
      log_and_notify("Nightly: #{cost_centre.key} raised #{error.class}: #{error.message}", error,
                     context: { source: "reimbursements_nightly_batch", cost_centre: cost_centre.key })
      return if dry_run

      recipients = Array(recipients).compact_blank
      return if recipients.empty?

      notify(cost_centre, recipients) do |emailer, to|
        emailer.failure(recipients: to, error_text: error.message, run_date: run_date(today))
      end
    end
```

Finally, update the class-level comment: replace the `Operator recipients:` paragraph with

```ruby
  # Operator recipients: the members of the cost centre's own notification role
  # (CostCentre#notification_role), resolved through NotificationRecipients,
  # which keeps the whole-portal REIMBURSEMENTS_OPERATOR_EMAIL override ahead of
  # it. A centre whose role is empty sends nothing, warns, and does NOT record
  # the run-day, so it keeps alarming rather than going quiet.
```

and delete the paragraph beginning "TODO(mysql): scope both queues per cost centre" wherever it survives.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
$CLEANENV bin/rails test test/jobs/reimbursements/nightly_batch_job_test.rb
```

Expected: PASS, whole file green — including the pre-existing cases for the failure email, the all-or-nothing `record_nightly_run!` gating, and the not-a-run-day skip.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/reimbursements/nightly_batch_job.rb test/jobs/reimbursements/nightly_batch_job_test.rb
git commit -m "feat(reimbursements): remind each cost centre about only its own claims"
```

---

### Task 6: Surface an empty role on Integration Status

**Files:**
- Modify: `app/controllers/admin/reimbursements/status_controller.rb`
- Modify: `app/views/admin/reimbursements/status/show.html.erb`
- Test: `test/functional/admin/reimbursements/status_controller_test.rb`

**Interfaces:**
- Consumes: `CostCentre#notification_role` (Task 1). The view reads the role's members directly rather than through `notification_role_empty?`, because it needs the member list anyway for the missing-permission line.
- Produces: `StatusController#finance_user_ids` -> `Set<Integer>` of user ids holding `manage`/`reimbursements_finance`, declared a `helper_method` so `show.html.erb` can call it.

- [ ] **Step 1: Write the failing test**

Append to `test/functional/admin/reimbursements/status_controller_test.rb`:

```ruby
test "flags a cost centre whose notification role has no members" do
  ::Reimbursements::CostCentre.default.notification_role.users.clear

  get :show

  assert_response :success
  assert_match "No notification recipients", response.body
end

test "does not flag a cost centre whose notification role has members" do
  role = ::Reimbursements::CostCentre.default.notification_role
  role.users << users(:member)

  get :show

  assert_response :success
  assert_no_match "No notification recipients", response.body
end

test "flags a notification-role member who lacks the finance permission" do
  role = ::Reimbursements::CostCentre.default.notification_role
  role.users << users(:member)

  get :show

  assert_response :success
  assert_match "cannot open the finance screens", response.body
end
```

The third test relies on `users(:member)` deliberately holding only backend + staffing permissions — the fixtures file says so explicitly, so it is a stable choice. The signed-in finance user in this file's `setup` is a different user; if it is `users(:member)`, sign in as `users(:committee)` instead and grant that user the finance permission, rather than changing the `member` fixture.

- [ ] **Step 2: Run it to verify it fails**

```bash
$CLEANENV bin/rails test test/functional/admin/reimbursements/status_controller_test.rb -n "/notification/"
```

Expected: FAIL — the string is nowhere in the page.

- [ ] **Step 3: Load the finance user ids in the controller**

In `app/controllers/admin/reimbursements/status_controller.rb`, replace the duplicated assignments at the top of `#show` and `#run` with a `before_action`, and add the lookup:

```ruby
      before_action :load_cost_centres

      def show
      end

      def run
        @checks = run_checks
        respond_to do |format|
          format.turbo_stream
          format.html { render :show }
        end
      end

      private

      def load_cost_centres
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.includes(notification_role: :users).order(:name)
      end

      # Who can actually open the finance screens. A notification role is
      # deliberately NOT filtered to these users -- the permission grid and the
      # mailing list are separate by design -- so a member of the role without
      # the permission is surfaced here rather than silently dropped: they would
      # be emailed about claims they cannot open.
      def finance_user_ids
        @finance_user_ids ||=
          Admin::Permission.where(action: "manage", subject_class: "reimbursements_finance")
                           .includes(roles: :users)
                           .flat_map(&:roles).flat_map(&:users).map(&:id).to_set
      end
      helper_method :finance_user_ids
```

(`helper_method` may sit here beside the method; the file already declares `class_attribute` at the top, so follow whichever placement the surrounding code uses.)

- [ ] **Step 4: Add the card to the view**

In `app/views/admin/reimbursements/status/show.html.erb`, insert between the "Last nightly run" card and the "Integration checks" card:

```erb
<%= render CardComponent.new(title: "Notification recipients", html_class: "mt-4") do %>
  <p class="text-sm text-gray-600 mb-3">
    Who gets each cost centre's nightly reminders — claims stuck awaiting approval, and the queue
    ready to batch. Change it under that cost centre's Settings.
  </p>
  <ul class="flex flex-col gap-3">
    <% @cost_centres.each do |cost_centre| %>
      <% members = cost_centre.notification_role&.users.to_a %>
      <li class="text-sm">
        <div class="flex items-center gap-2">
          <%= render(BadgeComponent.new(type: members.any? ? :info : :danger, pill: true)
                                   .with_content(members.any? ? pluralize(members.size, "member") : "No notification recipients")) %>
          <span><strong><%= cost_centre.name %></strong></span>
          <% if cost_centre.notification_role %>
            <span class="text-gray-500"><%= cost_centre.notification_role.name %></span>
          <% end %>
        </div>
        <% if members.empty? %>
          <p class="text-xs text-red-700 mt-1">
            Nobody gets this cost centre's reminders. The nightly logs a warning and retries rather
            than marking the day handled, so nothing is lost — but nothing is sent either.
          </p>
        <% end %>
        <% unpermitted = members.reject { |user| finance_user_ids.include?(user.id) } %>
        <% if unpermitted.any? %>
          <p class="text-xs text-amber-700 mt-1">
            <%= unpermitted.map(&:full_name).to_sentence %>
            <%= unpermitted.one? ? "is" : "are" %> in this role but
            <strong>cannot open the finance screens</strong>, so the reminders will point at claims
            they can't see. Grant them "Manage reimbursements finance" or remove them from the role.
          </p>
        <% end %>
      </li>
    <% end %>
  </ul>
<% end %>
```

Check that `BadgeComponent` accepts `:danger` — grep `app/components/badge_component.rb` for its allowed types and use whichever names the red variant if it differs.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
$CLEANENV bin/rails test test/functional/admin/reimbursements/status_controller_test.rb
```

Expected: PASS, whole file green.

- [ ] **Step 6: Verify it in the browser**

Start the dev server from the worktree (it has its own port via `mise.local.toml`) and look at the real page — "should render" is not "does render":

```bash
bin/dev
```

Visit `/admin/reimbursements/status` signed in as a finance user. Confirm: the red "No notification recipients" badge appears for a centre whose role is empty, and the amber line appears for a member lacking the permission. Stop `bin/dev` afterwards — a running dev server makes ~57 unrelated system tests fail.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/reimbursements/status_controller.rb app/views/admin/reimbursements/status/show.html.erb test/functional/admin/reimbursements/status_controller_test.rb
git commit -m "feat(reimbursements): badge a cost centre with no notification recipients"
```

---

### Task 7: Documentation and the full-suite gate

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/reimbursements/mysql-migration-and-roadmap.md`

- [ ] **Step 1: Record the traps in CLAUDE.md**

Add to the **Reimbursements portal** section of `CLAUDE.md`, after the nightly-job bullet. Keep it to the traps — this repo's convention is short sections, not feature tours:

```markdown
- **Operator reminders go to the cost centre's own `notification_role`, not to the finance
  permission** (`Reimbursements::NotificationRecipients`). The permission still gates every
  finance SCREEN globally — a Fringe admin can open a termtime claim, they just aren't emailed
  about it. `REIMBURSEMENTS_OPERATOR_EMAIL` stays whole-portal and overrides both.
  - **`roles.id` is a legacy INTEGER primary key**, so `notification_role_id` is `:integer`.
  - **A claim whose budget names no cost centre falls to the DEFAULT centre**, not to nobody
    (`NightlyBatchJob#claims_by_cost_centre_id`) — the same leniency as `DatabaseStore#in_year`.
    A claim reminded to the wrong admins is visible and correctable; one reminded to nobody
    leaves a producer waiting indefinitely.
  - **An empty role does NOT record the run-day.** The old code returned "delivered" for no
    recipients, which marked the day handled forever and lost the alert. It now warns, fires a
    `reimbursements.nightly_no_recipients` Honeybadger event, and retries tomorrow. The
    Integration Status page badges it, and also flags role members lacking the finance
    permission — they'd be emailed about claims they can't open.
  - Build Batch's `batch_ready` / `failure` are still **clicker-only**, deliberately.
```

- [ ] **Step 2: Close the roadmap item**

In `docs/reimbursements/mysql-migration-and-roadmap.md`, update the **Per-cost-centre expense scoping** bullet under "Deferred robustness items" to record what shipped and what did not:

```markdown
- **Per-cost-centre expense scoping.** *Partly done (2026-08-31.)* The nightly reminder is now
  scoped: `NightlyBatchJob` buckets claims by `budget -> cost_centre` and reminds each centre's
  own `notification_role`, so the `TODO(mysql)` hard skip of non-default centres is gone. **Build
  Batch and Reconcile are still global**, and expenses still carry no cost-centre column of their
  own — they resolve one through their budget, which needs no backfill and no sync-on-change.
  See `docs/superpowers/specs/2026-08-31-per-cost-centre-finance-notifications-design.md`.
```

- [ ] **Step 3: Run the full test suite**

Fixtures changed in Task 3, so `rails-core` rule 8 applies: the whole suite, not just the touched files. Check the power profile first — the same suite takes ~2 min on `performance` and ~9.5 min on `power-saver`:

```bash
powerprofilesctl get
docker start /mysql8
$CLEANENV bin/rails test 2>&1 | tail -40
```

Expected: green. Read the full output — do not `head`/`tail` away a failure you will have to re-run for.

- [ ] **Step 4: Run the system tests**

`bin/rails test` does not run them, and this change touched two admin views:

```bash
$CLEANENV bin/rails test:system 2>&1 | tail -40
```

Expected: green. Make sure `bin/dev` is stopped first, or ~57 unrelated system tests fail pointing nowhere near the cause.

- [ ] **Step 5: Run the pre-commit checks**

```bash
hk run check
```

Expected: green. `hk run fix` autofixes the formatting classes of failure. If `herb` reports a bogus ERB parse error, check the machine is not busy — its parser has a 1000ms timeout and reports a parse failure under load.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/reimbursements/mysql-migration-and-roadmap.md
git commit -m "docs(reimbursements): record the per-cost-centre notification traps"
```

- [ ] **Step 7: Merge**

Use the `superpowers:finishing-a-development-branch` skill. Before merging, confirm each of these — this change alters who receives production email, so a wrong answer is somebody silently stopping getting their reminders:

1. The full suite and the system tests are green, and `hk run check` passes.
2. `bin/rails db:rollback:primary STEP=1` followed by `bin/rails db:migrate` still works.
3. **On deploy, production's `Fringe Finance Admin` (id 59) is the notification role on the Fringe cost centre**, and its membership is what Mick set. Verify with `kamal app exec` after deploying — note that `kamal app exec` uses the deployed image, so it must run *after* the deploy, not before.
