# Box Office Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A set of public, self-updating web pages for the box office Anthias screen that can never render blank, covering upcoming shows, tonight's show and its credits, opportunities, news, and the archive.

**Architecture:** Each URL is a `Display::PagesController` action that resolves an ordered list of panels (`Display::Chain`) and renders the first one reporting content; every chain ends in `Panels::Identity`, which runs no query and is always available. A new nullable `events.performance_weekdays` column lets an event say which days it actually plays, which is what makes "is it on tonight" and "the next N events" answerable for a year-long weekly run like the Improverts.

**Tech Stack:** Rails 8.1, MySQL, Minitest (`test/functional` for controllers, `test/models`), FactoryBot, Tailwind v4 via Vite, `rqrcode` with `as_svg(standalone: false)`.

**Spec:** `docs/superpowers/specs/2026-08-23-box-office-display-design.md`

## Global Constraints

- **Every display route must render 200 with a non-blank body against an empty database.** This is the feature, not error handling. Task 4 builds the guarantee first; no later task may weaken it.
- **Blank `performance_weekdays` means every day of the run, including weekends.** Never Monday–Friday. No existing row is backfilled.
- **No type filter and no duration rule in the event pool.** Shows, workshops and seasons (festivals) all flow through. The only lever for a long run is `performance_weekdays`.
- **No curtain times anywhere.** The schema has none; do not invent or hardcode one.
- **The display layout must not load `application.css`** — it has unlayered `h1`–`h6` rules (`app/javascript/entrypoints/application.css:31,37`) that beat Tailwind utilities. Import `../styles/tailwind-base.css` only.
- **`Event` has `default_scope -> { order("end_date DESC") }`** (`app/models/event.rb:153`). Any query that needs its own order must use `.reorder`, never `.order`.
- **The `:show`/`:workshop`/`:season` factories set `is_public { [true, false].sample }`** — always pass `is_public: true` explicitly in tests, or they fail randomly.
- Run the test DB first: `docker start /mysql8`.
- Tests: `bin/rails test <path>`. Full suite before merge. `bin/rails test:system` separately for system tests.

---

### Task 1: `performance_weekdays` on Event

**Files:**
- Create: `db/migrate/20260823120000_add_performance_weekdays_to_events.rb`
- Modify: `app/models/event.rb`
- Test: `test/models/event_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Event#performance_wdays -> Array<Integer>`, `Event#on_today?(date = Date.current) -> Boolean`, `Event#next_occurrence(from = Date.current) -> Date | nil`. Tasks 3, 6 and 8 depend on these exact names.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/event_test.rb`, inside the existing test class:

```ruby
  # --- performance days -------------------------------------------------

  test "on_today? is true every day of the run when no performance days are set" do
    event = FactoryBot.create(:show, start_date: Date.current - 2, end_date: Date.current + 2, is_public: true)

    assert event.on_today?
    assert event.on_today?(Date.current + 1)
    assert_not event.on_today?(Date.current + 3)
  end

  test "on_today? is only true on the listed performance days" do
    friday = Date.current.next_occurring(:friday)
    event = FactoryBot.create(:show, start_date: friday - 30, end_date: friday + 30,
                                     is_public: true, performance_weekdays: "5")

    assert event.on_today?(friday)
    assert_not event.on_today?(friday + 1)
  end

  test "next_occurrence returns the next matching day inside the run" do
    friday = Date.current.next_occurring(:friday)
    event = FactoryBot.create(:show, start_date: friday - 30, end_date: friday + 30,
                                     is_public: true, performance_weekdays: "5")

    assert_equal friday, event.next_occurrence(friday - 3)
  end

  test "next_occurrence is the start date when the run has not begun" do
    event = FactoryBot.create(:show, start_date: Date.current + 10, end_date: Date.current + 12, is_public: true)

    assert_equal Date.current + 10, event.next_occurrence
  end

  test "next_occurrence is nil when the remaining run holds no performance day" do
    friday = Date.current.next_occurring(:friday)
    # Saturday to Thursday: no Friday is left in the range.
    event = FactoryBot.create(:show, start_date: friday + 1, end_date: friday + 6,
                                     is_public: true, performance_weekdays: "5")

    assert_nil event.next_occurrence(friday + 1)
  end

  test "next_occurrence is nil once the run has ended" do
    event = FactoryBot.create(:show, start_date: Date.current - 10, end_date: Date.current - 5, is_public: true)

    assert_nil event.next_occurrence
  end

  test "performance_weekdays normalises to a sorted deduped list and blanks to nil" do
    event = FactoryBot.build(:show, performance_weekdays: " 5, 1 ,5 ")
    assert_equal "1,5", event.performance_weekdays

    event.performance_weekdays = ""
    assert_nil event.performance_weekdays
  end

  test "performance_weekdays rejects day numbers outside 0..6" do
    event = FactoryBot.build(:show, performance_weekdays: "7")

    assert_not event.valid?
    assert event.errors[:performance_weekdays].present?
  end

  test "performance_wdays reads the stored list as integers" do
    event = FactoryBot.build(:show, performance_weekdays: "1,5")

    assert_equal [ 1, 5 ], event.performance_wdays
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
docker start /mysql8
bin/rails test test/models/event_test.rb
```

Expected: FAIL — `NoMethodError: undefined method 'on_today?'` and `unknown attribute 'performance_weekdays'`.

- [ ] **Step 3: Write the migration**

Create `db/migrate/20260823120000_add_performance_weekdays_to_events.rb`:

```ruby
class AddPerformanceWeekdaysToEvents < ActiveRecord::Migration[8.1]
  # Which days an event actually performs, as Date#wday integers (0 = Sunday),
  # comma separated. NULL means every day of the run -- which is exactly what a
  # bare date range has always meant here, so no existing row needs backfilling
  # and nobody has to invent performance days they do not know.
  #
  # This has to be stored because duration cannot answer "is it on tonight":
  # the Improverts run all year and play Fridays, while a three-week Fringe run
  # is also a long range and genuinely is on every night.
  def change
    add_column :events, :performance_weekdays, :string, limit: 255
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

Expected: `add_column(:events, :performance_weekdays, :string, {limit: 255})`. This also rewrites the `# == Schema Information` block on the Event models via the `db:migrate` annotaterb hook — that churn is expected, keep it.

- [ ] **Step 5: Add the length validation**

In `app/models/event.rb`, immediately after `validates :content_warnings, length: { maximum: 16777215 }` (line 83):

```ruby
  validates :performance_weekdays, length: { maximum: 255 }
```

- [ ] **Step 6: Add the normaliser and validation**

In `app/models/event.rb`, immediately after the existing `normalizes :name, :tagline, :slug, :author, :price, ...` line (line 136):

```ruby
  # Stored as sorted, comma-separated Date#wday integers. Deliberately does NOT
  # coerce with to_i: "abc".to_i is 0, which would silently mean Sunday. Junk is
  # kept intact so the validation below can reject it.
  normalizes :performance_weekdays, with: ->(value) {
    parts = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq.sort
    parts.empty? ? nil : parts.join(",")
  }

  validate :performance_weekdays_are_day_numbers
```

- [ ] **Step 7: Add the reader methods**

In `app/models/event.rb`, immediately after `def pretix_slug ... end` (lines 288-290):

```ruby
  # The days of the week this event actually performs, as Date#wday integers
  # (0 = Sunday). Empty means it plays every day of its run.
  def performance_wdays
    performance_weekdays.to_s.split(",").map(&:to_i)
  end

  def on_today?(date = Date.current)
    return false if start_date.nil? || end_date.nil?
    return false unless (start_date..end_date).cover?(date)

    performance_wdays.empty? || performance_wdays.include?(date.wday)
  end

  # The next date this event actually plays, on or after +from+; nil if it never
  # plays again. Weekdays repeat, so the answer is always within 7 days of the
  # search start -- there is no need to walk a year-long run.
  def next_occurrence(from = Date.current)
    return nil if start_date.nil? || end_date.nil?

    from = [ from, start_date ].max
    return nil if from > end_date
    return from if performance_wdays.empty?

    (from..[ from + 6, end_date ].min).find { |date| performance_wdays.include?(date.wday) }
  end
```

- [ ] **Step 8: Add the private validation method**

In `app/models/event.rb`, in the `private` section at the end of the class:

```ruby
  def performance_weekdays_are_day_numbers
    return if performance_weekdays.blank?
    return if performance_weekdays.split(",").all? { |part| part.match?(/\A[0-6]\z/) }

    errors.add(:performance_weekdays, "must be day numbers from 0 (Sunday) to 6 (Saturday)")
  end
```

- [ ] **Step 9: Run the tests to verify they pass**

```bash
bin/rails test test/models/event_test.rb
```

Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 10: Commit**

```bash
git add db/migrate db/schema.rb app/models/event.rb test/models/event_test.rb
git commit -m "feat(events): record which weekdays an event performs

Blank means every day of the run, which is what a bare date range has
always meant, so nothing is backfilled. Duration cannot answer this:
the Improverts run all year on Fridays, and a three-week Fringe run is
also a long range but genuinely is on every night."
```

---

### Task 2: Admin form field for performance days

**Files:**
- Modify: `app/models/event.rb`
- Modify: `app/views/admin/events/_basic_form.erb`
- Modify: `app/controllers/admin/generic_events_controller.rb:51-68`
- Modify: `config/locales/simple_form.en.yml`
- Test: `test/models/event_test.rb`, `test/functional/admin/shows_controller_test.rb`

**Interfaces:**
- Consumes: `Event#performance_wdays` (Task 1).
- Produces: `Event#performance_wdays_list -> Array<String>` and `Event#performance_wdays_list=(values)`, the form-facing accessor. No later task uses these.

- [ ] **Step 1: Write the failing accessor tests**

Append to `test/models/event_test.rb`:

```ruby
  test "performance_wdays_list reads the stored days as strings for the form" do
    event = FactoryBot.build(:show, performance_weekdays: "1,5")

    assert_equal %w[1 5], event.performance_wdays_list
  end

  test "performance_wdays_list= joins the checkbox values and drops the blank" do
    event = FactoryBot.build(:show)
    # simple_form check_boxes always post a leading "" from their hidden field.
    event.performance_wdays_list = [ "", "5", "1" ]

    assert_equal "1,5", event.performance_weekdays
  end

  test "performance_wdays_list= with nothing ticked clears the column" do
    event = FactoryBot.build(:show, performance_weekdays: "5")
    event.performance_wdays_list = [ "" ]

    assert_nil event.performance_weekdays
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/models/event_test.rb -n "/performance_wdays_list/"
```

Expected: FAIL — `NoMethodError: undefined method 'performance_wdays_list'`.

- [ ] **Step 3: Add the accessor**

In `app/models/event.rb`, directly below `next_occurrence`:

```ruby
  # Form-facing accessor. simple_form check_boxes hand back an array of strings
  # (with a leading "" from their hidden field); the column stores them joined.
  def performance_wdays_list
    performance_wdays.map(&:to_s)
  end

  def performance_wdays_list=(values)
    self.performance_weekdays = Array(values).reject(&:blank?).join(",")
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/models/event_test.rb -n "/performance_wdays_list/"
```

Expected: PASS.

- [ ] **Step 5: Add the form field**

In `app/views/admin/events/_basic_form.erb`, directly after the `f.input :end_date` line:

```erb
<%= f.input :performance_wdays_list,
      as: :check_boxes,
      collection: Date::DAYNAMES.each_with_index.map { |name, wday| [ name, wday ] },
      hint: 'Leave every box unticked if the event plays every day between the start and end dates — that is the normal case. Only tick days for something that runs a long time but plays intermittently, like the Improverts.' %>
```

- [ ] **Step 6: Permit the parameter**

In `app/controllers/admin/generic_events_controller.rb`, in the array returned by `permitted_params` (line 52), add next to `event_tag_ids: []`:

```ruby
      performance_wdays_list: [],
```

- [ ] **Step 7: Add the label**

In `config/locales/simple_form.en.yml`, under `simple_form.labels.defaults`:

```yaml
        performance_wdays_list: "Performance days"
```

- [ ] **Step 8: Write the failing controller test**

Append to `test/functional/admin/shows_controller_test.rb`, inside the existing `Admin::ShowsControllerTest` class:

```ruby
  test "updating a show stores the ticked performance days" do
    show = FactoryBot.create(:show, is_public: true)

    patch :update, params: { id: show.to_param, show: { performance_wdays_list: [ "", "5" ] } }

    assert_equal "5", show.reload.performance_weekdays
  end
```

- [ ] **Step 9: Run it**

```bash
bin/rails test test/functional/admin/shows_controller_test.rb
```

Expected: PASS. The file already has its own sign-in setup; do not add another.

- [ ] **Step 10: Verify the form renders**

Load `/admin/shows/<slug>/edit` in the running dev server and confirm seven checkboxes appear under the end date, labelled "Performance days". No "Translation missing" text.

- [ ] **Step 11: Commit**

```bash
git add app/models/event.rb app/views/admin/events/_basic_form.erb \
        app/controllers/admin/generic_events_controller.rb \
        config/locales/simple_form.en.yml test/
git commit -m "feat(admin): tick which weekdays an event performs

Unticked stays the normal case and means every day of the run."
```

---

### Task 3: `Display::EventPool`

**Files:**
- Create: `app/services/display/event_pool.rb`
- Test: `test/services/display/event_pool_test.rb`

**Interfaces:**
- Consumes: `Event#on_today?`, `Event#next_occurrence` (Task 1).
- Produces: `Display::EventPool.upcoming(on: Date.current) -> Array<Event>` and `Display::EventPool.slot(number, on: Date.current) -> Event | nil`. Tasks 5, 6, 8 and 9 depend on these.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/event_pool_test.rb`:

```ruby
require "test_helper"

class Display::EventPoolTest < ActiveSupport::TestCase
  test "an event on today sorts ahead of one that started earlier but is not" do
    friday = Date.current.next_occurring(:friday)

    # Started long ago, plays Fridays only, so it is not on today unless today
    # happens to be a Friday.
    weekly = FactoryBot.create(:show, name: "Improverts", is_public: true,
                                      start_date: Date.current - 60, end_date: Date.current + 60,
                                      performance_weekdays: friday.wday.to_s)
    running = FactoryBot.create(:show, name: "Tonight", is_public: true,
                                       start_date: Date.current - 1, end_date: Date.current + 1)

    pool = Display::EventPool.upcoming

    assert_equal running.id, pool.first.id
    assert_includes pool.map(&:id), weekly.id
  end

  test "the pool orders by next occurrence, not by start date" do
    soon  = FactoryBot.create(:show, is_public: true, start_date: Date.current + 2, end_date: Date.current + 3)
    later = FactoryBot.create(:show, is_public: true, start_date: Date.current + 9, end_date: Date.current + 10)

    assert_equal [ soon.id, later.id ], Display::EventPool.upcoming.map(&:id)
  end

  test "a season is in the pool like any other event" do
    festival = FactoryBot.create(:season, is_public: true,
                                          start_date: Date.current + 1, end_date: Date.current + 4)

    assert_includes Display::EventPool.upcoming.map(&:id), festival.id
  end

  test "a workshop is in the pool" do
    workshop = FactoryBot.create(:workshop, is_public: true,
                                            start_date: Date.current + 1, end_date: Date.current + 2)

    assert_includes Display::EventPool.upcoming.map(&:id), workshop.id
  end

  test "private and finished events are excluded" do
    private_event = FactoryBot.create(:show, is_public: false, start_date: Date.current, end_date: Date.current + 1)
    finished      = FactoryBot.create(:show, is_public: true, start_date: Date.current - 9, end_date: Date.current - 8)

    ids = Display::EventPool.upcoming.map(&:id)

    assert_not_includes ids, private_event.id
    assert_not_includes ids, finished.id
  end

  test "an event whose remaining run holds no performance day drops out" do
    friday = Date.current.next_occurring(:friday)
    stale = FactoryBot.create(:show, is_public: true,
                                     start_date: friday + 1, end_date: friday + 6,
                                     performance_weekdays: "5")

    assert_not_includes Display::EventPool.upcoming(on: friday + 1).map(&:id), stale.id
  end

  test "slots wrap around when there are fewer events than slots" do
    events = 4.times.map do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + (i * 2) + 1,
                               end_date: Date.current + (i * 2) + 2)
    end

    got = (1..6).map { |slot| Display::EventPool.slot(slot).id }

    assert_equal [ events[0], events[1], events[2], events[3], events[0], events[1] ].map(&:id), got
  end

  test "slot returns nil when the pool is empty" do
    Event.delete_all

    assert_nil Display::EventPool.slot(1)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/event_pool_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Display::EventPool`.

- [ ] **Step 3: Write the implementation**

Create `app/services/display/event_pool.rb`:

```ruby
module Display
  # The single ordered list of events behind the slot pages, the What's On board
  # and the credits page.
  #
  # There is deliberately NO type filter and no duration rule. A Season is
  # normally a festival -- exactly what the box office should be advertising --
  # not a term-long container, and the only lever for an unusually long run is
  # performance_weekdays. A duration rule here would also drop a three-week
  # Fringe run, which genuinely is on every night.
  #
  # Ordering happens in Ruby rather than SQL: the pool is a handful of rows and
  # the weekday logic does not belong in a query.
  class EventPool
    # Not Event.current -- that scope hardcodes Date.current, so it would ignore
    # the +on+ argument the ordering is tested with.
    def self.upcoming(on: Date.current)
      Event.where(is_public: true)
           .where("end_date >= ?", on)
           .includes(image_attachment: :blob)
           .to_a
           .select { |event| event.next_occurrence(on).present? }
           .sort_by { |event| [ event.on_today?(on) ? 0 : 1, event.next_occurrence(on) ] }
    end

    # Slot numbers are 1-based and wrap: six slots against four events shows
    # events 1, 2, 3, 4, 1, 2. Repeating a poster beats a dark screen.
    def self.slot(number, on: Date.current)
      pool = upcoming(on: on)
      return nil if pool.empty?

      pool[(number - 1) % pool.size]
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/event_pool_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/display/event_pool.rb test/services/display/event_pool_test.rb
git commit -m "feat(display): ordered event pool with wrapping slots

Anything on today sorts first, so slot 1 is tonight's show when there
is one. No type or duration filter: a Season is normally a festival."
```

---

### Task 4: The display shell and the never-blank guarantee

This task builds the guarantee **first**: every route exists and renders the identity card. Later tasks slot real panels in front of it, and the test written here must keep passing throughout.

**Files:**
- Create: `app/services/display/chain.rb`
- Create: `app/services/display/panels/base.rb`
- Create: `app/services/display/panels/identity.rb`
- Create: `app/controllers/display/pages_controller.rb`
- Create: `app/views/layouts/display.html.erb`
- Create: `app/views/display/pages/panel.html.erb`
- Create: `app/views/display/panels/_identity.html.erb`
- Create: `app/javascript/entrypoints/display.css`
- Modify: `config/routes.rb`
- Test: `test/functional/display/pages_controller_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Display::Chain.new(*panels).resolve -> panel`; `Display::Panels::Base` with `#available? -> Boolean`, `#partial -> String`, `#locals -> Hash`; `Display::Panels::Identity`. Every later task subclasses `Base` and appends its panel to a chain in `Display::PagesController`.

- [ ] **Step 1: Write the failing test**

Create `test/functional/display/pages_controller_test.rb`:

```ruby
require "test_helper"

class Display::PagesControllerTest < ActionController::TestCase
  # Anthias plays a fixed playlist of URLs forever, so a page that renders
  # nothing is not a blank page for a moment -- it is a blank screen in the box
  # office until somebody notices and reconfigures the Pi. Every route has to
  # survive an empty database. This test is the feature.
  PAGES = [
    [ :whats_on,     {} ],
    [ :next_event,   { slot: "1" } ],
    [ :next_event,   { slot: "6" } ],
    [ :credits,      {} ],
    [ :get_involved, {} ],
    [ :news,         {} ],
    [ :on_this_day,  {} ]
  ].freeze

  test "every display page renders against an empty database" do
    empty_the_database!

    PAGES.each do |action, params|
      get action, params: params

      assert_response :success, "#{action} #{params} did not render"
      assert response.body.present?, "#{action} #{params} rendered a blank body"
      assert_match "Bedlam", response.body, "#{action} #{params} rendered nothing recognisable"
    end
  end

  test "every display page renders with content present" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 3)

    PAGES.each do |action, params|
      get action, params: params

      assert_response :success, "#{action} #{params} did not render"
      assert response.body.present?, "#{action} #{params} rendered a blank body"
    end
  end

  test "display pages are not cached and not indexed" do
    get :whats_on

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_match "noindex", response.headers["X-Robots-Tag"]
  end

  private

  # delete_all in child-first order: several of these associations are declared
  # restrict_with_error, and delete_all bypasses that but not the FK columns.
  def empty_the_database!
    TeamMember.delete_all
    Review.delete_all
    Picture.delete_all
    Admin::Questionnaires::Questionnaire.delete_all
    Admin::Feedback.delete_all
    Event.delete_all
    OpportunityRole.delete_all
    Opportunity.delete_all
    News.delete_all
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
docker start /mysql8
bin/rails test test/functional/display/pages_controller_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Display::PagesController`.

- [ ] **Step 3: Write the chain and the panel base**

Create `app/services/display/chain.rb`:

```ruby
module Display
  # An ordered list of panels; the first that reports content is what renders.
  #
  # Every chain must end with Panels::Identity, which runs no query and is
  # therefore always available. That is what makes it impossible for a URL in
  # the Anthias playlist to render blank.
  class Chain
    class NoPanelAvailableError < StandardError; end

    def initialize(*panels)
      @panels = panels
    end

    def resolve
      @panels.find(&:available?) ||
        raise(NoPanelAvailableError, "no panel reported content; every chain must end in Panels::Identity")
    end
  end
end
```

Create `app/services/display/panels/base.rb`:

```ruby
module Display
  module Panels
    # A panel answers three questions: does it have anything to show, which
    # partial draws it, and what does that partial need.
    class Base
      def available?
        raise NotImplementedError
      end

      def partial
        raise NotImplementedError
      end

      def locals
        {}
      end
    end
  end
end
```

Create `app/services/display/panels/identity.rb`:

```ruby
module Display
  module Panels
    # The terminal panel in every chain. It runs no query, so it cannot fail
    # and is always available.
    class Identity < Base
      def available?
        true
      end

      def partial
        "display/panels/identity"
      end
    end
  end
end
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/display/pages_controller.rb`. Every action chains to `Identity` alone for now; later tasks put real panels in front.

```ruby
# Pages for the box office Anthias screen. Public and unauthenticated -- every
# page shows what is already public elsewhere on the site.
class Display::PagesController < ApplicationController
  layout "display"
  skip_authorization_check

  before_action :set_display_headers

  def whats_on
    render_chain(Display::Panels::Identity.new)
  end

  def next_event
    render_chain(Display::Panels::Identity.new)
  end

  def credits
    render_chain(Display::Panels::Identity.new)
  end

  def get_involved
    render_chain(Display::Panels::Identity.new)
  end

  def news
    render_chain(Display::Panels::Identity.new)
  end

  def on_this_day
    render_chain(Display::Panels::Identity.new)
  end

  private

  def render_chain(*panels)
    @panel = Display::Chain.new(*panels).resolve
    render "panel"
  end

  def set_display_headers
    # Anthias must never hold a stale frame, and these pages have no business
    # in a search index.
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
```

- [ ] **Step 5: Write the layout and stylesheet**

Create `app/javascript/entrypoints/display.css`:

```css
/* The box office display screen.
 *
 * Deliberately does NOT import application.css: that file carries unlayered
 * h1-h6 rules (lines 31 and 37) that beat Tailwind utilities, and every size on
 * this screen is set to be read from across a room. */
@import "../styles/tailwind-base.css";
```

Create `app/views/layouts/display.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Bedlam Theatre</title>
  <meta name="robots" content="noindex, nofollow">

  <%= vite_client_tag %>
  <%= vite_stylesheet_tag "display.css", "data-turbo-track": "reload" %>
</head>
<%# No JavaScript entrypoint on purpose: this screen has no interaction, and
    the application bundle would pull in Stimulus controllers it cannot use. %>
<body class="overflow-hidden bg-neutral-950 text-white">
  <main class="h-screen w-screen overflow-hidden">
    <%= yield %>
  </main>
</body>
</html>
```

Create `app/views/display/pages/panel.html.erb`:

```erb
<%= render partial: @panel.partial, locals: @panel.locals %>
```

Create `app/views/display/panels/_identity.html.erb`:

```erb
<%# locals: () %>
<div class="flex h-full w-full flex-col items-center justify-center gap-8 bg-neutral-950">
  <h1 class="text-8xl font-bold tracking-tight text-white">Bedlam Theatre</h1>
  <p class="text-4xl text-neutral-400">bedlamtheatre.co.uk</p>
</div>
```

- [ ] **Step 6: Add the routes**

In `config/routes.rb`, after the `resources :venues do ... end` block:

```ruby
  # The box office display screen (Anthias). Public and unauthenticated: it
  # shows only what is already public on the site. Anthias plays a fixed
  # playlist of these URLs forever, so each one falls back through a chain of
  # panels and can never render blank.
  namespace :display do
    get "whats-on",        to: "pages#whats_on",     as: :whats_on
    get "next/:slot",      to: "pages#next_event",   as: :next_event, constraints: { slot: /[1-6]/ }
    get "tonight-credits", to: "pages#credits",      as: :credits
    get "get-involved",    to: "pages#get_involved", as: :get_involved
    get "news",            to: "pages#news",         as: :news
    get "on-this-day",     to: "pages#on_this_day",  as: :on_this_day
  end
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
bin/rails test test/functional/display/pages_controller_test.rb
```

Expected: PASS. The first run is slow — `config/vite.json` sets `autoBuild: true` for test, so adding `display.css` triggers a Vite rebuild.

- [ ] **Step 8: Look at it**

With `bin/dev` already running, open `http://localhost:3000/display/whats-on`. Expect a black screen with "Bedlam Theatre" centred in large white type. If the heading renders at browser-default size, `display.css` is not being picked up.

- [ ] **Step 9: Commit**

```bash
git add app/services/display app/controllers/display app/views/layouts/display.html.erb \
        app/views/display app/javascript/entrypoints/display.css config/routes.rb test/functional/display
git commit -m "feat(display): panel chain, layout and routes for the box office screen

Every route renders the identity card, which runs no query. Later panels
go in front of it; the empty-database test must keep passing."
```

---

### Task 5: What's On board

**Files:**
- Create: `app/services/display/panels/whats_on.rb`
- Create: `app/views/display/panels/_whats_on.html.erb`
- Create: `app/helpers/display_helper.rb`
- Modify: `app/controllers/display/pages_controller.rb`
- Test: `test/services/display/panels/whats_on_test.rb`, `test/helpers/display_helper_test.rb`

**Interfaces:**
- Consumes: `Display::EventPool.upcoming` (Task 3), `Display::Panels::Base` (Task 4).
- Produces: `Display::Panels::WhatsOn.new(on: Date.current)`; `DisplayHelper#display_date_range(event) -> String` and `#display_when(event, on:) -> String`. Task 6 uses `display_when`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/panels/whats_on_test.rb`:

```ruby
require "test_helper"

class Display::Panels::WhatsOnTest < ActiveSupport::TestCase
  test "is unavailable when there is nothing upcoming" do
    Event.delete_all

    assert_not Display::Panels::WhatsOn.new.available?
  end

  test "is available and lists upcoming events when there are some" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)

    panel = Display::Panels::WhatsOn.new

    assert panel.available?
    assert_includes panel.locals[:events].map(&:id), show.id
  end

  test "caps the board at eight rows" do
    Event.delete_all
    12.times do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + i + 1, end_date: Date.current + i + 2)
    end

    assert_equal 8, Display::Panels::WhatsOn.new.locals[:events].size
  end
end
```

Create `test/helpers/display_helper_test.rb`:

```ruby
require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper

  test "display_date_range collapses a single day" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 3))

    assert_equal "Tue 3 Mar", display_date_range(event)
  end

  test "display_date_range drops the repeated month" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_date_range(event)
  end

  test "display_date_range keeps both months when the run crosses one" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 30), end_date: Date.new(2026, 4, 2))

    assert_equal "Mon 30 Mar – Thu 2 Apr", display_date_range(event)
  end

  test "display_when says the weekday for a run that plays one day a week" do
    # A year-long range tells nobody when to turn up; "Every Friday" does.
    event = FactoryBot.build(:show, start_date: Date.new(2026, 9, 1), end_date: Date.new(2027, 6, 30),
                                    performance_weekdays: "5")

    assert_equal "Every Friday", display_when(event)
  end

  test "display_when falls back to the range when no performance days are set" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/panels/whats_on_test.rb test/helpers/display_helper_test.rb
```

Expected: FAIL — uninitialized constants `Display::Panels::WhatsOn` and `DisplayHelper`.

- [ ] **Step 3: Write the helper**

Create `app/helpers/display_helper.rb`:

```ruby
module DisplayHelper
  # "Tue 3 Mar", or "Tue 3 - Sat 7 Mar" when both ends share a month.
  def display_date_range(event)
    starts = event.start_date
    ends   = event.end_date

    return starts.strftime("%a %-d %b") if starts == ends
    return "#{starts.strftime('%a %-d')} – #{ends.strftime('%a %-d %b')}" if starts.month == ends.month

    "#{starts.strftime('%a %-d %b')} – #{ends.strftime('%a %-d %b')}"
  end

  # What to print in the "when" column. For an event that plays intermittently
  # the raw range is useless on a screen -- "Sep 1 - Jun 30" tells nobody when
  # to turn up -- so name the night instead.
  def display_when(event, on: Date.current)
    wdays = event.performance_wdays

    return display_date_range(event) if wdays.empty?
    return "Every #{Date::DAYNAMES[wdays.first]}" if wdays.one?

    occurrence = event.next_occurrence(on)
    occurrence ? occurrence.strftime("%a %-d %b") : display_date_range(event)
  end
end
```

- [ ] **Step 4: Write the panel**

Create `app/services/display/panels/whats_on.rb`:

```ruby
module Display
  module Panels
    class WhatsOn < Base
      ROWS = 8

      def initialize(on: Date.current)
        @on = on
      end

      def available?
        events.any?
      end

      def partial
        "display/panels/whats_on"
      end

      def locals
        { events: events, on: @on }
      end

      private

      def events
        @events ||= Display::EventPool.upcoming(on: @on).first(ROWS)
      end
    end
  end
end
```

- [ ] **Step 5: Write the partial**

Create `app/views/display/panels/_whats_on.html.erb`:

```erb
<%# locals: (events:, on:) %>
<div class="flex h-full w-full flex-col bg-neutral-950 px-16 py-12">
  <h1 class="mb-10 text-7xl font-bold tracking-tight text-primary">What's On</h1>

  <ul class="flex flex-1 flex-col divide-y divide-neutral-800">
    <% events.each do |event| %>
      <li class="flex items-baseline gap-10 py-4">
        <span class="w-[26rem] shrink-0 text-4xl font-semibold text-neutral-300">
          <%= display_when(event, on: on) %>
        </span>
        <span class="min-w-0 flex-1 truncate text-5xl font-bold text-white"><%= event.name %></span>
        <span class="w-64 shrink-0 truncate text-right text-3xl text-neutral-400"><%= event.price %></span>
      </li>
    <% end %>
  </ul>

  <p class="mt-8 text-3xl text-neutral-500">bedlamtheatre.co.uk</p>
</div>
```

- [ ] **Step 6: Wire it into the chains**

In `app/controllers/display/pages_controller.rb`, replace the `whats_on` action:

```ruby
  def whats_on
    render_chain(
      Display::Panels::WhatsOn.new,
      Display::Panels::Identity.new
    )
  end
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/panels/whats_on_test.rb test/helpers/display_helper_test.rb test/functional/display/pages_controller_test.rb
```

Expected: PASS, including the empty-database guarantee from Task 4.

- [ ] **Step 8: Look at it**

Open `http://localhost:3000/display/whats-on`. Expect a red "What's On" heading and a list of upcoming events with dates and prices.

- [ ] **Step 9: Commit**

```bash
git add app/services/display/panels/whats_on.rb app/views/display/panels/_whats_on.html.erb \
        app/helpers/display_helper.rb app/controllers/display/pages_controller.rb test/
git commit -m "feat(display): What's On board

An intermittent run prints its night ('Every Friday') rather than a
year-long date range nobody can act on."
```

---

### Task 6: Next event slots, tonight mode and QR codes

**Files:**
- Create: `app/services/display/panels/next_event.rb`
- Create: `app/views/display/panels/_next_event.html.erb`
- Modify: `app/helpers/display_helper.rb`
- Modify: `app/controllers/display/pages_controller.rb`
- Test: `test/services/display/panels/next_event_test.rb`, `test/helpers/display_helper_test.rb`

**Interfaces:**
- Consumes: `Display::EventPool.slot` (Task 3), `DisplayHelper#display_when` (Task 5).
- Produces: `Display::Panels::NextEvent.new(slot, on: Date.current)`; `DisplayHelper#display_qr_code(url, css_class:)`, `#display_booking_url(event)`, `#display_image_url(event)`. Tasks 7, 8 and 9 use `display_qr_code` and `display_image_url`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/panels/next_event_test.rb`:

```ruby
require "test_helper"

class Display::Panels::NextEventTest < ActiveSupport::TestCase
  test "is unavailable when the pool is empty" do
    Event.delete_all

    assert_not Display::Panels::NextEvent.new(1).available?
  end

  test "slot 1 is the show running today" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current + 5, end_date: Date.current + 6)
    tonight = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    panel = Display::Panels::NextEvent.new(1)

    assert panel.available?
    assert_equal tonight.id, panel.locals[:event].id
    assert panel.locals[:tonight], "an event running today should render in tonight mode"
  end

  test "a slot beyond the pool wraps back to the start" do
    first  = FactoryBot.create(:show, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)
    second = FactoryBot.create(:show, is_public: true, start_date: Date.current + 3, end_date: Date.current + 4)

    assert_equal first.id,  Display::Panels::NextEvent.new(3).locals[:event].id
    assert_equal second.id, Display::Panels::NextEvent.new(4).locals[:event].id
  end

  test "an upcoming event that is not on today is not in tonight mode" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current + 3, end_date: Date.current + 4)

    assert_not Display::Panels::NextEvent.new(1).locals[:tonight]
  end
end
```

Append to `test/helpers/display_helper_test.rb`:

```ruby
  test "display_qr_code renders an inline svg with no xml declaration" do
    svg = display_qr_code("https://example.com")

    assert_match(/\A<svg /, svg)
    assert_no_match(/<\?xml/, svg)
    assert_match(/viewbox=/i, svg)
  end

  test "display_booking_url points at the pretix shop when tickets are shown" do
    event = FactoryBot.build(:show, slug: "the-crucible", pretix_shown: true, pretix_slug_override: nil)

    assert_equal "https://tickets.bedlamtheatre.co.uk/the-crucible/", display_booking_url(event)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/panels/next_event_test.rb test/helpers/display_helper_test.rb
```

Expected: FAIL — `uninitialized constant Display::Panels::NextEvent`, `undefined method 'display_qr_code'`.

- [ ] **Step 3: Add the helpers**

Append to `app/helpers/display_helper.rb`:

```ruby
  QR_MODULE_SIZE = 4

  # Inline SVG, so the page makes no external request and nothing has to be
  # added to the CSP.
  #
  # standalone: false is what makes this inlineable -- standalone: true prefixes
  # an <?xml?> declaration, which an HTML parser swallows as a bogus comment.
  # It also omits the <svg> wrapper, so we supply one with a viewBox and let CSS
  # size it.
  def display_qr_code(url, css_class: "h-64 w-64")
    qr = RQRCode::QRCode.new(url, level: :m)
    extent = qr.modules.length * QR_MODULE_SIZE
    body = qr.as_svg(module_size: QR_MODULE_SIZE, standalone: false, use_path: true,
                     color: "000000", fill: "ffffff")

    tag.svg(body.html_safe, # rubocop:disable Rails/OutputSafety
            xmlns: "http://www.w3.org/2000/svg",
            viewBox: "0 0 #{extent} #{extent}",
            class: css_class,
            role: "img",
            "aria-label": "Scan to book")
  end

  def display_booking_url(event)
    return pretix_event_url(event) if event.pretix_shown?

    "#{request.base_url}#{polymorphic_path(event)}"
  end

  # The 1920x1200 variant, not slideshow_image_url's 960x500 -- this is a 1080p
  # screen and the smaller one visibly upscales.
  #
  # fetch_image attaches a generated placeholder when nothing is uploaded, so
  # this always returns something. That is a write on a read path, but it is
  # idempotent and matches what the public event pages already do.
  def display_image_url(event)
    rails_representation_url(event.fetch_image.variant(large_display_variant).processed, only_path: true)
  end
```

- [ ] **Step 4: Write the panel**

Create `app/services/display/panels/next_event.rb`:

```ruby
module Display
  module Panels
    # One slot of the rotation. Slots wrap, so six slots against four events
    # repeat the first two rather than leaving a dark screen.
    class NextEvent < Base
      def initialize(slot, on: Date.current)
        @slot = slot
        @on = on
      end

      def available?
        event.present?
      end

      def partial
        "display/panels/next_event"
      end

      def locals
        { event: event, tonight: event.on_today?(@on), on: @on }
      end

      private

      def event
        return @event if defined?(@event)

        @event = Display::EventPool.slot(@slot, on: @on)
      end
    end
  end
end
```

- [ ] **Step 5: Write the partial**

Create `app/views/display/panels/_next_event.html.erb`:

```erb
<%# locals: (event:, tonight:, on:) %>
<div class="relative h-full w-full overflow-hidden bg-neutral-950">
  <%= image_tag display_image_url(event), class: "absolute inset-0 h-full w-full object-cover", alt: "" %>

  <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black via-black/90 to-transparent px-16 pb-14 pt-48">
    <div class="flex items-end gap-14">
      <div class="min-w-0 flex-1">
        <% if tonight %>
          <p class="mb-4 text-4xl font-bold uppercase tracking-[0.3em] text-primary">Tonight</p>
        <% end %>

        <h1 class="truncate text-8xl font-bold leading-none text-white"><%= event.name %></h1>

        <% if event.author.present? %>
          <p class="mt-4 text-4xl text-neutral-300">by <%= event.author %></p>
        <% end %>

        <p class="mt-8 text-5xl font-semibold text-white"><%= display_when(event, on: on) %></p>

        <% if event.price.present? %>
          <p class="mt-3 text-4xl text-neutral-300"><%= event.price %></p>
        <% end %>

        <% if tonight && event.content_warnings.present? %>
          <p class="mt-8 max-w-5xl text-3xl leading-snug text-amber-300">
            Content warnings: <%= truncate(event.content_warnings.to_s, length: 180) %>
          </p>
        <% end %>
      </div>

      <div class="shrink-0 text-center">
        <%= display_qr_code(display_booking_url(event)) %>
        <p class="mt-4 text-2xl uppercase tracking-widest text-neutral-200">Book</p>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 6: Wire it into the chains**

In `app/controllers/display/pages_controller.rb`, replace `next_event` and update `whats_on`:

```ruby
  def whats_on
    render_chain(
      Display::Panels::WhatsOn.new,
      Display::Panels::NextEvent.new(1),
      Display::Panels::Identity.new
    )
  end

  def next_event
    render_chain(
      Display::Panels::NextEvent.new(params[:slot].to_i),
      Display::Panels::WhatsOn.new,
      Display::Panels::Identity.new
    )
  end
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/panels/next_event_test.rb test/helpers/display_helper_test.rb test/functional/display/pages_controller_test.rb
```

Expected: PASS.

- [ ] **Step 8: Look at it**

Open `http://localhost:3000/display/next/1`. Expect full-bleed artwork with the title over a dark gradient and a white QR square bottom right. Scan the QR with a phone and confirm it opens the ticket shop or the event page.

- [ ] **Step 9: Commit**

```bash
git add app/services/display/panels/next_event.rb app/views/display/panels/_next_event.html.erb \
        app/helpers/display_helper.rb app/controllers/display/pages_controller.rb test/
git commit -m "feat(display): event slot pages with tonight mode and booking QR

Slot 1 is tonight's show whenever one is running, because the pool
sorts anything on today to the front. No curtain time is printed: the
schema has none."
```

---

### Task 7: News and Get Involved panels

**Files:**
- Create: `app/services/display/panels/news.rb`, `app/services/display/panels/get_involved.rb`
- Create: `app/views/display/panels/_news.html.erb`, `app/views/display/panels/_get_involved.html.erb`
- Modify: `app/controllers/display/pages_controller.rb`
- Test: `test/services/display/panels/news_test.rb`, `test/services/display/panels/get_involved_test.rb`

**Interfaces:**
- Consumes: `Display::Panels::Base` (Task 4), `DisplayHelper#display_qr_code` (Task 6).
- Produces: `Display::Panels::News.new`, `Display::Panels::GetInvolved.new`. Task 9 puts `News` in the On This Day chain.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/panels/news_test.rb`:

```ruby
require "test_helper"

class Display::Panels::NewsTest < ActiveSupport::TestCase
  test "is unavailable when there is no published news" do
    News.delete_all

    assert_not Display::Panels::News.new.available?
  end

  test "shows the most recently published public item" do
    News.delete_all
    FactoryBot.create(:news, show_public: true, publish_date: 3.days.ago, title: "Older")
    newest = FactoryBot.create(:news, show_public: true, publish_date: 1.day.ago, title: "Newest")

    panel = Display::Panels::News.new

    assert panel.available?
    assert_equal newest.id, panel.locals[:article].id
  end

  test "ignores private and future-dated items" do
    News.delete_all
    FactoryBot.create(:news, show_public: false, publish_date: 1.day.ago)
    FactoryBot.create(:news, show_public: true, publish_date: 3.days.from_now)

    assert_not Display::Panels::News.new.available?
  end
end
```

Create `test/services/display/panels/get_involved_test.rb`:

```ruby
require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  test "is unavailable when nothing is open" do
    Opportunity.delete_all

    assert_not Display::Panels::GetInvolved.new.available?
  end

  test "lists only active opportunities, capped at five" do
    panel = Display::Panels::GetInvolved.new

    assert panel.available?
    assert_operator panel.locals[:opportunities].size, :<=, 5
    assert panel.locals[:opportunities].all?(&:active?), "every listed opportunity should be active"
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/panels/news_test.rb test/services/display/panels/get_involved_test.rb
```

Expected: FAIL — uninitialized constants.

- [ ] **Step 3: Write the panels**

Create `app/services/display/panels/news.rb`:

```ruby
module Display
  module Panels
    class News < Base
      def available?
        article.present?
      end

      def partial
        "display/panels/news"
      end

      def locals
        { article: article }
      end

      private

      # News carries default_scope -> { order("publish_date DESC") }, so first
      # is the most recent.
      def article
        return @article if defined?(@article)

        @article = ::News.where(show_public: true).current.first
      end
    end
  end
end
```

Create `app/services/display/panels/get_involved.rb`:

```ruby
module Display
  module Panels
    class GetInvolved < Base
      LIMIT = 5

      def available?
        opportunities.any?
      end

      def partial
        "display/panels/get_involved"
      end

      def locals
        { opportunities: opportunities }
      end

      private

      def opportunities
        @opportunities ||= Opportunity.active.includes(:company, :roles).limit(LIMIT).to_a
      end
    end
  end
end
```

- [ ] **Step 4: Write the partials**

Create `app/views/display/panels/_news.html.erb`:

```erb
<%# locals: (article:) %>
<div class="flex h-full w-full flex-col justify-center bg-neutral-950 px-24 py-16">
  <p class="mb-8 text-4xl font-bold uppercase tracking-[0.3em] text-primary">Latest News</p>

  <h1 class="text-8xl font-bold leading-tight text-white"><%= article.title %></h1>

  <p class="mt-10 max-w-6xl text-4xl leading-relaxed text-neutral-300">
    <%# The body is markdown, not HTML. Truncating the raw source is good enough
        for a headline card and avoids rendering markdown on a screen nobody
        can scroll. %>
    <%= truncate(article.body.to_s, length: 320, separator: " ") %>
  </p>

  <p class="mt-12 text-3xl text-neutral-500"><%= article.publish_date&.strftime("%-d %B %Y") %></p>
</div>
```

Create `app/views/display/panels/_get_involved.html.erb`:

```erb
<%# locals: (opportunities:) %>
<div class="flex h-full w-full flex-col bg-neutral-950 px-16 py-12">
  <h1 class="mb-10 text-7xl font-bold tracking-tight text-primary">Get Involved</h1>

  <ul class="flex flex-1 flex-col divide-y divide-neutral-800">
    <% opportunities.each do |opportunity| %>
      <li class="py-5">
        <p class="truncate text-5xl font-bold text-white"><%= opportunity.display_title %></p>
        <% if opportunity.roles.any? %>
          <p class="mt-2 truncate text-3xl text-neutral-400">
            <%= opportunity.roles.map(&:position).join(" · ") %>
          </p>
        <% end %>
      </li>
    <% end %>
  </ul>

  <div class="mt-8 flex items-center gap-8">
    <%= display_qr_code("#{request.base_url}#{get_involved_opportunities_path}", css_class: "h-40 w-40") %>
    <p class="text-4xl text-neutral-300">Scan for the full list and to apply</p>
  </div>
</div>
```

- [ ] **Step 5: Wire them into the chains**

In `app/controllers/display/pages_controller.rb`:

```ruby
  def get_involved
    render_chain(
      Display::Panels::GetInvolved.new,
      Display::Panels::WhatsOn.new,
      Display::Panels::News.new,
      Display::Panels::Identity.new
    )
  end

  def news
    render_chain(
      Display::Panels::News.new,
      Display::Panels::WhatsOn.new,
      Display::Panels::GetInvolved.new,
      Display::Panels::Identity.new
    )
  end
```

News also completes the two chains that were waiting on it, matching the chain
table in the spec. Replace `whats_on` and `next_event` as well:

```ruby
  def whats_on
    render_chain(
      Display::Panels::WhatsOn.new,
      Display::Panels::NextEvent.new(1),
      Display::Panels::News.new,
      Display::Panels::Identity.new
    )
  end

  def next_event
    render_chain(
      Display::Panels::NextEvent.new(params[:slot].to_i),
      Display::Panels::WhatsOn.new,
      Display::Panels::News.new,
      Display::Panels::Identity.new
    )
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/panels/news_test.rb test/services/display/panels/get_involved_test.rb test/functional/display/pages_controller_test.rb
```

Expected: PASS.

- [ ] **Step 7: Look at it**

Open `http://localhost:3000/display/news` and `http://localhost:3000/display/get-involved`.

- [ ] **Step 8: Commit**

```bash
git add app/services/display/panels/news.rb app/services/display/panels/get_involved.rb \
        app/views/display/panels/_news.html.erb app/views/display/panels/_get_involved.html.erb \
        app/controllers/display/pages_controller.rb test/
git commit -m "feat(display): news headline and get involved pages"
```

---

### Task 8: Tonight's credits

**Files:**
- Create: `app/services/display/panels/credits.rb`
- Create: `app/views/display/panels/_credits.html.erb`
- Modify: `app/controllers/display/pages_controller.rb`
- Test: `test/services/display/panels/credits_test.rb`

**Interfaces:**
- Consumes: `Display::EventPool.upcoming` (Task 3), `TeamMember.ordered` and `TeamMember#cast?`/`#cast_display_name` (existing).
- Produces: `Display::Panels::Credits.new(on: Date.current)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/panels/credits_test.rb`:

```ruby
require "test_helper"

class Display::Panels::CreditsTest < ActiveSupport::TestCase
  test "is unavailable when nothing is upcoming" do
    Event.delete_all

    assert_not Display::Panels::Credits.new.available?
  end

  test "is unavailable when the show has no team recorded" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    assert_not Display::Panels::Credits.new.available?
  end

  test "prefers the show running today over the next one" do
    later = FactoryBot.create(:show, is_public: true, team_member_count: 2,
                                     start_date: Date.current + 5, end_date: Date.current + 6)
    tonight = FactoryBot.create(:show, is_public: true, team_member_count: 2,
                                       start_date: Date.current, end_date: Date.current + 1)

    panel = Display::Panels::Credits.new

    assert panel.available?
    assert_equal tonight.id, panel.locals[:event].id
    assert_not_equal later.id, panel.locals[:event].id
  end

  test "falls back to the next show when nothing runs today" do
    upcoming = FactoryBot.create(:show, is_public: true, team_member_count: 3,
                                        start_date: Date.current + 4, end_date: Date.current + 5)

    assert_equal upcoming.id, Display::Panels::Credits.new.locals[:event].id
  end

  test "splits cast from crew" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)
    FactoryBot.create(:team_member, teamwork: show, position: "Actor (Abigail)")
    FactoryBot.create(:team_member, teamwork: show, position: "Lighting Designer")

    locals = Display::Panels::Credits.new.locals

    assert_equal 1, locals[:cast].size
    assert_equal 1, locals[:crew].size
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/panels/credits_test.rb
```

Expected: FAIL — `uninitialized constant Display::Panels::Credits`.

- [ ] **Step 3: Write the panel**

Create `app/services/display/panels/credits.rb`:

```ruby
module Display
  module Panels
    class Credits < Base
      def initialize(on: Date.current)
        @on = on
      end

      def available?
        event.present? && members.any?
      end

      def partial
        "display/panels/credits"
      end

      def locals
        cast, crew = members.partition(&:cast?)

        { event: event, cast: cast, crew: crew, tonight: event.on_today?(@on) }
      end

      private

      def pool
        @pool ||= Display::EventPool.upcoming(on: @on)
      end

      def event
        return @event if defined?(@event)

        @event = pool.find { |candidate| candidate.on_today?(@on) } || pool.first
      end

      # preload rather than includes: TeamMember.ordered already joins users to
      # order by them, and preload fetches the records without fighting it.
      def members
        @members ||= event ? event.team_members.ordered.preload(:user).to_a : []
      end
    end
  end
end
```

- [ ] **Step 4: Write the partial**

Create `app/views/display/panels/_credits.html.erb`:

```erb
<%# locals: (event:, cast:, crew:, tonight:) %>
<%
  # A 90-seat house still puts up big casts. Shrink the type once the list gets
  # long rather than letting it run off a screen nobody can scroll.
  total = cast.size + crew.size
  name_size = total > 24 ? "text-2xl" : (total > 14 ? "text-3xl" : "text-4xl")
%>
<div class="flex h-full w-full flex-col bg-neutral-950 px-16 py-12">
  <p class="mb-3 text-3xl font-bold uppercase tracking-[0.3em] text-primary">
    <%= tonight ? "Tonight" : "Coming Up" %>
  </p>
  <h1 class="mb-10 truncate text-7xl font-bold text-white"><%= event.name %></h1>

  <div class="grid flex-1 grid-cols-2 gap-16 overflow-hidden">
    <div>
      <h2 class="mb-5 text-3xl font-semibold uppercase tracking-widest text-neutral-500">Cast</h2>
      <ul class="space-y-2">
        <% cast.each do |member| %>
          <li class="<%= name_size %> text-white">
            <span class="font-semibold"><%= member.user_name %></span>
            <span class="text-neutral-400"><%= member.cast_display_name %></span>
          </li>
        <% end %>
      </ul>
    </div>

    <div>
      <h2 class="mb-5 text-3xl font-semibold uppercase tracking-widest text-neutral-500">Company</h2>
      <ul class="space-y-2">
        <% crew.each do |member| %>
          <li class="<%= name_size %> text-white">
            <span class="font-semibold"><%= member.user_name %></span>
            <span class="text-neutral-400"><%= member.position %></span>
          </li>
        <% end %>
      </ul>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Wire it into the chain**

In `app/controllers/display/pages_controller.rb`:

```ruby
  def credits
    render_chain(
      Display::Panels::Credits.new,
      Display::Panels::NextEvent.new(1),
      Display::Panels::WhatsOn.new,
      Display::Panels::Identity.new
    )
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/panels/credits_test.rb test/functional/display/pages_controller_test.rb
```

Expected: PASS.

- [ ] **Step 7: Look at it**

Open `http://localhost:3000/display/tonight-credits`. Confirm two columns, no overflow off the bottom of a 1080-tall viewport.

- [ ] **Step 8: Commit**

```bash
git add app/services/display/panels/credits.rb app/views/display/panels/_credits.html.erb \
        app/controllers/display/pages_controller.rb test/
git commit -m "feat(display): cast and company for tonight's show"
```

---

### Task 9: On this day

**Files:**
- Create: `app/services/display/panels/on_this_day.rb`
- Create: `app/views/display/panels/_on_this_day.html.erb`
- Modify: `app/controllers/display/pages_controller.rb`
- Test: `test/services/display/panels/on_this_day_test.rb`

**Interfaces:**
- Consumes: `Event.on_date` (existing scope), `DisplayHelper#display_image_url` (Task 6).
- Produces: `Display::Panels::OnThisDay.new(on: Date.current)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/display/panels/on_this_day_test.rb`:

```ruby
require "test_helper"

class Display::Panels::OnThisDayTest < ActiveSupport::TestCase
  setup do
    Event.delete_all
  end

  # A one-day run on today's month and day, N years back.
  def archive_show(years_ago:, attach_image: true, run_days: 0, is_public: true)
    start_date = Date.new(Date.current.year - years_ago, Date.current.month, Date.current.day)

    FactoryBot.create(:show, is_public: is_public, attach_image: attach_image,
                             start_date: start_date, end_date: start_date + run_days)
  end

  test "is unavailable when nothing matches" do
    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "finds an old show that ran on this day" do
    show = archive_show(years_ago: 12)

    panel = Display::Panels::OnThisDay.new

    assert panel.available?
    assert_equal show.id, panel.locals[:event].id
    assert_equal 12, panel.locals[:years_ago]
  end

  test "prefers the oldest match so the pick is deterministic" do
    oldest = archive_show(years_ago: 20)
    archive_show(years_ago: 5)

    assert_equal oldest.id, Display::Panels::OnThisDay.new.locals[:event].id
  end

  test "excludes anything that ended less than a year ago" do
    archive_show(years_ago: 0)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes a run longer than sixty days" do
    # A residency or a term-long season matches most of the calendar and is not
    # an "on this day" story.
    archive_show(years_ago: 8, run_days: 90)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes an event with no real artwork" do
    # fetch_image would attach a generated placeholder, so the guard has to be a
    # join on the attachment, checked before anything calls fetch_image.
    archive_show(years_ago: 8, attach_image: false)

    assert_not Display::Panels::OnThisDay.new.available?
  end

  test "excludes a private event" do
    archive_show(years_ago: 8, is_public: false)

    assert_not Display::Panels::OnThisDay.new.available?
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/services/display/panels/on_this_day_test.rb
```

Expected: FAIL — `uninitialized constant Display::Panels::OnThisDay`.

- [ ] **Step 3: Write the panel**

Create `app/services/display/panels/on_this_day.rb`:

```ruby
module Display
  module Panels
    # Something from the archive that ran on today's date in an earlier year.
    #
    # Event.on_date matches on month and day only, and its own comment records
    # that it deliberately skips runs crossing the new year (the Imps,
    # Candlewasters). Bedlam does not programme across the new year, so that gap
    # costs nothing and is cheaper than a second scope kept in step with it.
    class OnThisDay < Base
      MAX_RUN_DAYS = 60

      def initialize(on: Date.current)
        @on = on
      end

      def available?
        event.present?
      end

      def partial
        "display/panels/on_this_day"
      end

      def locals
        { event: event, years_ago: @on.year - event.start_date.year }
      end

      private

      def event
        return @event if defined?(@event)

        @event = Event.on_date(@on)
                      .where(is_public: true)
                      .where("end_date < ?", @on - 1.year)
                      .where("DATEDIFF(end_date, start_date) <= ?", MAX_RUN_DAYS)
                      # fetch_image attaches a generated placeholder, so "has
                      # artwork" has to be asked of the database, before anything
                      # calls it.
                      .joins(:image_attachment)
                      # reorder, not order: Event's default_scope is end_date DESC,
                      # so order would append and "oldest" would mean something else.
                      .reorder(:start_date)
                      .first
      end
    end
  end
end
```

- [ ] **Step 4: Write the partial**

Create `app/views/display/panels/_on_this_day.html.erb`:

```erb
<%# locals: (event:, years_ago:) %>
<div class="relative h-full w-full overflow-hidden bg-neutral-950">
  <%= image_tag display_image_url(event), class: "absolute inset-0 h-full w-full object-cover opacity-70", alt: "" %>

  <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black via-black/90 to-transparent px-16 pb-16 pt-48">
    <p class="mb-4 text-4xl font-bold uppercase tracking-[0.3em] text-primary">
      On this day, <%= pluralize(years_ago, "year") %> ago
    </p>

    <h1 class="truncate text-8xl font-bold leading-none text-white"><%= event.name %></h1>

    <% if event.author.present? %>
      <p class="mt-4 text-4xl text-neutral-300">by <%= event.author %></p>
    <% end %>

    <p class="mt-6 text-4xl text-neutral-400"><%= display_date_range(event) %></p>
  </div>
</div>
```

- [ ] **Step 5: Wire it into the chain**

In `app/controllers/display/pages_controller.rb`:

```ruby
  def on_this_day
    render_chain(
      Display::Panels::OnThisDay.new,
      Display::Panels::News.new,
      Display::Panels::WhatsOn.new,
      Display::Panels::Identity.new
    )
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bin/rails test test/services/display/panels/on_this_day_test.rb test/functional/display/pages_controller_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/display/panels/on_this_day.rb app/views/display/panels/_on_this_day.html.erb \
        app/controllers/display/pages_controller.rb test/
git commit -m "feat(display): on this day from the archive

Guarded on a real attachment, because fetch_image would otherwise hand
back a generated placeholder for every event without artwork."
```

---

### Task 10: Setup page

**Files:**
- Create: `app/controllers/display/setup_controller.rb`
- Create: `app/views/display/setup/show.html.erb`
- Modify: `config/routes.rb`
- Test: `test/functional/display/setup_controller_test.rb`

**Interfaces:**
- Consumes: the display routes (Task 4).
- Produces: nothing other tasks use.

- [ ] **Step 1: Write the failing test**

Create `test/functional/display/setup_controller_test.rb`:

```ruby
require "test_helper"

class Display::SetupControllerTest < ActionController::TestCase
  test "lists every display url with a suggested duration" do
    get :show

    assert_response :success
    assert_match "/display/whats-on", response.body
    assert_match "/display/next/6", response.body
    assert_match "/display/on-this-day", response.body
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/functional/display/setup_controller_test.rb
```

Expected: FAIL — `uninitialized constant Display::SetupController`.

- [ ] **Step 3: Write the controller**

Create `app/controllers/display/setup_controller.rb`:

```ruby
# Whoever sets up the Raspberry Pi copies the playlist off this page rather than
# out of a chat log or a commit message.
class Display::SetupController < ApplicationController
  skip_authorization_check

  # Durations in seconds. A poster wants dwelling on; a headline is read once.
  PLAYLIST = [
    { path: "/display/next/1", seconds: 20, note: "Tonight's show when one is running, else the next one" },
    { path: "/display/next/2", seconds: 20, note: "Second event in the pool" },
    { path: "/display/next/3", seconds: 20, note: "Third" },
    { path: "/display/next/4", seconds: 20, note: "Fourth" },
    { path: "/display/next/5", seconds: 20, note: "Fifth (repeats an earlier one if the pool is short)" },
    { path: "/display/next/6", seconds: 20, note: "Sixth (likewise)" },
    { path: "/display/whats-on", seconds: 18, note: "The upcoming schedule board" },
    { path: "/display/tonight-credits", seconds: 18, note: "Cast and company for tonight's show" },
    { path: "/display/get-involved", seconds: 15, note: "Open opportunities" },
    { path: "/display/news", seconds: 12, note: "Latest news headline" },
    { path: "/display/on-this-day", seconds: 15, note: "Something from the archive" }
  ].freeze

  def show
    @playlist = PLAYLIST
  end
end
```

- [ ] **Step 4: Write the view**

Create `app/views/display/setup/show.html.erb` (this one uses the ordinary site layout, since a person reads it):

```erb
<% @title = "Box office display setup" %>

<h1>Box office display setup</h1>

<p>
  Add each of these as a web-page asset in Anthias, in this order. They can stay
  in the playlist permanently: every page falls back to something else when it
  has nothing of its own to show, so none of them can go blank.
</p>

<table class="table">
  <thead>
    <tr><th>URL</th><th>Duration</th><th>What it shows</th></tr>
  </thead>
  <tbody>
    <% @playlist.each do |entry| %>
      <tr>
        <td><code><%= "#{request.base_url}#{entry[:path]}" %></code></td>
        <td><%= entry[:seconds] %>s</td>
        <td><%= entry[:note] %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 5: Add the route**

In `config/routes.rb`, as the first line inside the `namespace :display do` block:

```ruby
    root to: "setup#show"
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bin/rails test test/functional/display/setup_controller_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/display/setup_controller.rb app/views/display/setup config/routes.rb test/
git commit -m "feat(display): setup page listing the Anthias playlist"
```

---

### Task 11: Full verification and documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/plans/2026-08-23-box-office-display.md` (tick the boxes)

- [ ] **Step 1: Run the full test suite**

```bash
docker start /mysql8
bin/rails test 2>&1 | tail -40
```

Expected: 0 failures, 0 errors. Read the whole output — do not pipe through `head`.

Note: a shell with fnox-exported `REIMBURSEMENTS_*` variables makes unrelated credential tests fail. Strip them before a manual run.

- [ ] **Step 2: Run the system tests**

```bash
bin/rails test:system 2>&1 | tail -40
```

Expected: only the known pre-existing `test/system/konami_code_test.rb` `ActiveStorage::FileNotFoundError`.

- [ ] **Step 3: Run the pre-commit checks**

```bash
hk run check
```

Fix anything `rubocop`, `herb`, `eslint` or `jscpd` reports. `jscpd` gates at threshold 0 — the panel partials share a layout idiom, so if it flags duplication between `_next_event` and `_on_this_day`, extract the shared full-bleed frame into `app/views/display/panels/_artwork_frame.html.erb` and render it from both.

- [ ] **Step 4: Verify the real pages visually**

Use the `vischeck:verify` skill against a 1920x1080 viewport for each of:
`/display/whats-on`, `/display/next/1`, `/display/tonight-credits`, `/display/get-involved`, `/display/news`, `/display/on-this-day`.

Check specifically: nothing overflows the bottom edge, the QR squares are white-on-dark and unclipped, and no heading has reverted to browser-default sizing (which would mean `display.css` is not loading).

- [ ] **Step 5: Document it in CLAUDE.md**

Add a short section, traps only — per the house style, keep it to what would bite someone:

```markdown
## Box office display (Anthias)

Public, unauthenticated pages at `/display/*` for the box office screen; `/display` lists
the playlist. Spec: `docs/superpowers/specs/2026-08-23-box-office-display-design.md`.

- **Anthias plays a fixed playlist forever, so no page may render blank.** Every route is a
  `Display::Chain` of panels ending in `Panels::Identity`, which runs no query. The
  empty-database test in `test/functional/display/pages_controller_test.rb` is the guarantee —
  don't weaken it.
- **`events.performance_weekdays` (blank = every day of the run) is what makes "on tonight"
  answerable.** Duration can't: the Improverts run all year on Fridays, and a three-week Fringe
  run is also a long range but genuinely is on every night. There is no type or duration filter
  in `Display::EventPool` — a `Season` is normally a festival and belongs on the screen.
- **The display layout must not load `application.css`** — its unlayered `h1`–`h6` rules beat
  Tailwind utilities. `display.css` imports `tailwind-base.css` only.
- **"On this day" joins `:image_attachment`** rather than checking `image.attached?`, because
  `Event#fetch_image` attaches a generated placeholder and would make every event pass.
- **No curtain times**: the schema has none. Don't hardcode one.
```

- [ ] **Step 6: Commit and merge**

```bash
git add CLAUDE.md docs/superpowers/plans/2026-08-23-box-office-display.md
git commit -m "docs(display): record the box office display traps"
```

Then use the `superpowers:finishing-a-development-branch` skill to merge `box-office-display` into `main` and remove the worktree.
