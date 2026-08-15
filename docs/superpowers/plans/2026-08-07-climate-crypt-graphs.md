# Crypt condensation-risk and ventilation charts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a condensation-risk view (margin chart + at-risk figures + per-day bars) and a ventilation chart to `/admin/climate`, fed by a new "in the crypt" flag on sensors.

**Architecture:** Two extractions from `Climate::SeriesQuery` (`Buckets`, `SeriesColors`) so four chart payloads share one bucketing and one colour rule, then three new query services on top. On the client, the shared Chart.js machinery moves to `app/javascript/lib/climate_chart.js` and four thin Stimulus controllers use it.

**Tech Stack:** Rails 8.1, MySQL, minitest, Stimulus, Vite, Chart.js (lazily imported), Tailwind v4.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-07-climate-crypt-graphs-design.md`. Read it before starting. Its "Decisions" section is settled.
- **Margin is `MIN(temperature_c - dew_point_c)`** — computed per row, then minimised. Never `MIN(temperature_c) - MAX(dew_point_c)`.
- **At-risk denominators are hours that have readings**, never hours in the range.
- **A coverage gap breaks a continuous spell.**
- **Never bucket with `UNIX_TIMESTAMP`.** The mysql2 adapter does not pin the session `time_zone`, so it reads the stored value in the server's zone and shifts every bucket boundary. Use the existing `TIME_TO_SEC(TIME(recorded_at)) % n` form from a frozen allow-list.
- **Threshold:** `Climate::CONDENSATION_RISK_MARGIN = 3.0`, and "at risk" means **strictly below** it (`margin < threshold`), matching the existing `climate_condensation_risk?`.
- **Test DB:** run `docker start /mysql8` before any test run.
- **Strip fnox env vars** when running the suite by hand: prefix with `env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID`.
- **`bin/rails test` does not run system tests.** `bin/rails test:system` does.
- **jscpd is gating at threshold 0.** Duplicated JS across the four chart controllers will fail the build. This is why Task 8 exists.
- **Rollbacks are namespaced:** `bin/rails db:rollback:primary STEP=1`.
- **Never use `btn btn-*` Bootstrap classes.** Use `btn_classes(...)`.
- **Commit style:** Conventional Commits, scope `climate`. Every commit ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
  ```

---

### Task 1: The `in_crypt` flag

**Files:**
- Create: `db/migrate/20260807210000_add_in_crypt_to_climate_sensors.rb`
- Modify: `app/models/climate/sensor.rb`
- Modify: `app/controllers/admin/climate/sensors_controller.rb:77-79` (`sensor_params`)
- Modify: `app/views/admin/climate/sensors/_form.html.erb`
- Modify: `app/views/admin/climate/sensors/index.html.erb`
- Modify: `test/support/climate_test_helpers.rb`
- Test: `test/models/climate/sensor_test.rb`, `test/functional/admin/climate/sensors_controller_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Climate::Sensor#in_crypt?`, `Climate::Sensor.in_crypt` (scope), `create_climate_sensor(in_crypt:)` test helper.

- [ ] **Step 1: Add `in_crypt:` to the test helper**

In `test/support/climate_test_helpers.rb`, add the keyword to `create_climate_sensor` and pass it through:

```ruby
  def create_climate_sensor(display_name: "Crypt, north wall", source: Climate::Sensor::SOURCE_GOVEE,
                            placement: Climate::Sensor::PLACEMENT_INDOOR,
                            active: true, location: nil, position: 0,
                            latitude: nil, longitude: nil, in_crypt: false)
    Climate::Sensor.create!(
      display_name: display_name, source: source, placement: placement,
      active: active, location: location, position: position,
      latitude: latitude, longitude: longitude, in_crypt: in_crypt
    )
  end
```

- [ ] **Step 2: Write the failing model tests**

Append to `test/models/climate/sensor_test.rb` (inside the existing class):

```ruby
  test "the outdoor feed cannot be marked as being in the crypt" do
    sensor = outdoor_climate_sensor
    sensor.in_crypt = true

    assert_not sensor.valid?
    assert sensor.errors[:in_crypt].present?
  end

  test "an indoor sensor can be marked as being in the crypt" do
    sensor = create_climate_sensor(in_crypt: true)

    assert_predicate sensor, :valid?
    assert_predicate sensor, :in_crypt?
  end

  test "the in_crypt scope returns only the ticked sensors" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    create_climate_sensor(display_name: "Dressing room", in_crypt: false)

    assert_equal [ crypt.id ], Climate::Sensor.in_crypt.pluck(:id)
  end
```

- [ ] **Step 3: Run them to verify they fail**

```bash
docker start /mysql8
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/models/climate/sensor_test.rb
```
Expected: FAIL — `unknown attribute 'in_crypt'`.

- [ ] **Step 4: Write the migration**

`db/migrate/20260807210000_add_in_crypt_to_climate_sensors.rb`:

```ruby
class AddInCryptToClimateSensors < ActiveRecord::Migration[8.1]
  # Which sensors are "the crypt" has to be stored rather than inferred:
  # placement already separates indoor from outdoor, but a dressing-room or
  # upstairs sensor is indoor too and would poison a crypt-only worst case.
  #
  # Backfilling here is safe, unlike Sensor.outdoor_source! — that had to be
  # ensured at runtime because test and CI databases are schema-LOADED, so a
  # migration would leave every environment except production without the row.
  # A backfill only has to touch rows that already exist, and those have none.
  def change
    add_column :climate_sensors, :in_crypt, :boolean, default: false, null: false

    reversible do |direction|
      direction.up do
        execute(<<~SQL.squish)
          UPDATE climate_sensors
          SET in_crypt = TRUE
          WHERE placement = 'indoor' AND source = 'govee'
        SQL
      end
    end
  end
end
```

- [ ] **Step 5: Add the scope and validation**

In `app/models/climate/sensor.rb`, after the existing `scope :in_display_order` line:

```ruby
    # Which sensors the condensation-risk and ventilation charts read.
    scope :in_crypt, -> { where(in_crypt: true) }
```

After the existing `validates` block:

```ruby
    validate :outdoor_feed_is_not_in_the_crypt
```

And in the instance methods, after `def outdoor?`:

```ruby
    private

    # The Open-Meteo row models the air outside the building. Letting it be
    # ticked would put the outdoor line into the crypt's own worst case.
    def outdoor_feed_is_not_in_the_crypt
      errors.add(:in_crypt, "cannot be set on the outdoor feed") if in_crypt? && outdoor?
    end
```

Note: `to_label` must stay above the `private` keyword — it is called from views.

- [ ] **Step 6: Migrate and run the tests**

```bash
bin/rails db:migrate
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/models/climate/sensor_test.rb
```
Expected: PASS.

- [ ] **Step 7: Verify the rollback actually runs**

```bash
bin/rails db:rollback:primary STEP=1
bin/rails db:migrate
```
Expected: both succeed, and `db/schema.rb` is unchanged after the round trip (`git diff db/schema.rb` shows only the `in_crypt` column added once).

- [ ] **Step 8: Permit the parameter and add the checkbox**

`app/controllers/admin/climate/sensors_controller.rb` — extend `sensor_params`:

```ruby
      def sensor_params
        params.require(:climate_sensor).permit(:display_name, :location, :active, :position, :in_crypt)
      end
```

`app/views/admin/climate/sensors/_form.html.erb` — after the `:active` input:

```erb
  <%= f.input :in_crypt, as: :boolean, label: "In the crypt",
              hint: "Include this sensor in the condensation-risk and ventilation charts." %>
```

`app/views/admin/climate/sensors/index.html.erb` — add a header after `Active`:

```erb
          <th scope="col">In crypt</th>
```

and the matching cell after the `active?` one:

```erb
            <td><%= sensor.in_crypt? ? "Yes" : "No" %></td>
```

- [ ] **Step 9: Write and run the controller test**

Append to `test/functional/admin/climate/sensors_controller_test.rb` (inside the existing class):

```ruby
      test "a manager can tick a sensor as being in the crypt" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: sensor.display_name, in_crypt: "1" } }

        assert_predicate sensor.reload, :in_crypt?
      end
```

The file's `setup` block already signs in a user holding `grant_climate_manage_permission`, so this test needs no extra setup.

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/functional/admin/climate/sensors_controller_test.rb test/models/climate/sensor_test.rb
```
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add db/migrate db/schema.rb app/models/climate/sensor.rb \
        app/controllers/admin/climate/sensors_controller.rb \
        app/views/admin/climate/sensors test/support/climate_test_helpers.rb \
        test/models/climate/sensor_test.rb test/functional/admin/climate/sensors_controller_test.rb
git commit -m "feat(climate): mark which sensors sit in the crypt

$(cat <<'MSG'
placement already separates indoor from outdoor, but a dressing-room sensor
is indoor too and would poison a crypt-only worst case. Backfills existing
indoor Govee sensors, which is safe here because a backfill only touches rows
that already exist and schema-loaded test databases have none.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 2: Extract `Buckets` and `SeriesColors`

**Files:**
- Create: `app/services/climate/buckets.rb`, `app/services/climate/series_colors.rb`
- Modify: `app/services/climate/series_query.rb`
- Test: `test/services/climate/buckets_test.rb`, `test/services/climate/series_colors_test.rb`

**Interfaces:**
- Consumes: `Climate::DateRange#days`, `#starts_at`, `#ends_at`.
- Produces:
  - `Climate::Buckets.new(range)` → `#seconds` (Integer), `#expression` (String SQL), `#aggregated?` (Boolean), `#to_time(bucket)` → `ActiveSupport::TimeWithZone`, `#with_gaps(points, keys:)` → Array of Hashes with `:t` as an ISO 8601 String.
  - `Climate::SeriesColors.new` → `#index_for(sensor)` → Integer.

This is a pure refactor: `SeriesQuery`'s public API and output are unchanged, so its existing test file must pass untouched.

- [ ] **Step 1: Write the failing `Buckets` tests**

`test/services/climate/buckets_test.rb`:

```ruby
require "test_helper"

class Climate::BucketsTest < ActiveSupport::TestCase
  def buckets(from:, to:)
    Climate::Buckets.new(Climate::DateRange.from_params({ from: from, to: to }))
  end

  test "keeps raw ten-minute buckets over a short span" do
    assert_equal 600, buckets(from: "2026-08-05", to: "2026-08-06").seconds
  end

  test "buckets hourly over a fortnight" do
    assert_equal 3_600, buckets(from: "2026-07-25", to: "2026-08-06").seconds
  end

  test "buckets six-hourly over a quarter" do
    assert_equal 21_600, buckets(from: "2026-06-01", to: "2026-08-06").seconds
  end

  test "buckets daily over a year" do
    assert_equal 86_400, buckets(from: "2025-08-06", to: "2026-08-06").seconds
  end

  test "raw resolution is not aggregated, wider ones are" do
    assert_not_predicate buckets(from: "2026-08-05", to: "2026-08-06"), :aggregated?
    assert_predicate buckets(from: "2026-07-25", to: "2026-08-06"), :aggregated?
  end

  # The mysql2 adapter does not pin the session time_zone, so a UNIX_TIMESTAMP
  # bucket would read the stored value in the SERVER's zone and shift every
  # boundary by its offset. This is the guard against someone "simplifying" it.
  test "every bucket expression is timezone-independent arithmetic" do
    Climate::Buckets::BUCKET_EXPRESSIONS.each_value do |expression|
      assert_no_match(/UNIX_TIMESTAMP/i, expression)
    end
  end

  test "inserts an explicit null point across a gap so the line breaks" do
    subject = buckets(from: "2026-07-25", to: "2026-08-06")
    points = [
      { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 },
      { t: Time.zone.parse("2026-08-05 20:00"), margin: 5.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_equal 3, result.size
    assert_nil result[1][:margin]
    assert_equal Time.zone.parse("2026-08-05 13:00").iso8601, result[1][:t]
  end

  test "leaves a contiguous run alone" do
    subject = buckets(from: "2026-07-25", to: "2026-08-06")
    points = [
      { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 },
      { t: Time.zone.parse("2026-08-05 13:00"), margin: 5.0 }
    ]

    assert_equal 2, subject.with_gaps(points, keys: [ :margin ]).size
  end

  test "renders every timestamp as an iso8601 string" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = [ { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 } ]

    assert_kind_of String, subject.with_gaps(points, keys: [ :margin ]).first[:t]
  end
end
```

- [ ] **Step 2: Write the failing `SeriesColors` test**

`test/services/climate/series_colors_test.rb`:

```ruby
require "test_helper"

class Climate::SeriesColorsTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Colour follows the sensor, not its position in a selection: deactivating
  # one sensor must not repaint the others, and a sensor must be the same
  # colour on every chart on the page.
  test "a sensor keeps its index when a lower-id sensor is left out" do
    first = create_climate_sensor(display_name: "North")
    second = create_climate_sensor(display_name: "South")

    both = Climate::SeriesColors.new

    assert_equal both.index_for(second), Climate::SeriesColors.new.index_for(second)
    assert_not_equal both.index_for(first), both.index_for(second)
  end

  test "an unknown sensor falls back to the first colour" do
    sensor = create_climate_sensor
    colors = Climate::SeriesColors.new
    sensor.destroy

    assert_equal 0, colors.index_for(sensor)
  end
end
```

- [ ] **Step 3: Run both to verify they fail**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/buckets_test.rb test/services/climate/series_colors_test.rb
```
Expected: FAIL — `uninitialized constant Climate::Buckets`.

- [ ] **Step 4: Write `Climate::Buckets`**

`app/services/climate/buckets.rb`:

```ruby
module Climate
  ##
  # How wide a chart bucket is for a given span, the SQL that floors a
  # timestamp into one, and where a series has to BREAK rather than be drawn
  # across.
  #
  # Extracted from SeriesQuery so the four chart payloads share one rule: a
  # margin line bucketed differently from the temperature line above it would
  # be unreadable next to it.
  class Buckets
    HOUR = 3_600

    # Bucket width by span. Each keeps a series under about 800 points.
    RESOLUTIONS = [
      { max_days: 2,   seconds: 600 },     # raw
      { max_days: 14,  seconds: HOUR },
      { max_days: 90,  seconds: 6 * HOUR },
      { max_days: nil, seconds: 24 * HOUR }
    ].freeze

    # A frozen allow-list, so nothing user-supplied can reach the SQL string.
    #
    # NOT FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(recorded_at)/n)*n): the mysql2
    # adapter stores UTC but does not pin the session time_zone, so
    # UNIX_TIMESTAMP() reads the stored value in the SERVER's zone and every
    # bucket boundary silently shifts by its offset. The arithmetic below is
    # timezone-independent for any bucket that divides a day.
    BUCKET_EXPRESSIONS = {
      600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 600) SECOND)",
      3_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)",
      21_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 21600) SECOND)",
      86_400 => "DATE(recorded_at)"
    }.freeze

    # A break longer than this many buckets is drawn as a gap rather than a line.
    GAP_BUCKETS = 3

    RAW_SECONDS = RESOLUTIONS.first[:seconds]

    attr_reader :seconds

    def initialize(range)
      @seconds = RESOLUTIONS.find { |r| r[:max_days].nil? || range.days <= r[:max_days] }[:seconds]
    end

    def expression = BUCKET_EXPRESSIONS.fetch(seconds)

    # False when each bucket holds at most one reading, which is when a
    # min-max band would be a zero-width artefact rather than a spread.
    def aggregated? = seconds > RAW_SECONDS

    # DATE() buckets come back as a Date, the DATE_SUB ones as a Time.
    def to_time(bucket)
      bucket.is_a?(Date) && !bucket.is_a?(Time) ? bucket.beginning_of_day.in_time_zone : bucket.in_time_zone
    end

    # An explicit null wherever the series skips, so the chart BREAKS the line
    # rather than interpolating across an outage. A line drawn through missing
    # data is not cosmetic. It is a reading of the room that never happened.
    def with_gaps(points, keys:)
      threshold = seconds * GAP_BUCKETS
      blank = keys.index_with(nil)

      points.each_with_object([]) do |current, result|
        previous = result.last
        result << blank.merge(t: previous[:t] + seconds) if previous && (current[:t] - previous[:t]) > threshold
        result << current
      end.map { |entry| entry.merge(t: entry[:t].iso8601) }
    end
  end
end
```

- [ ] **Step 5: Write `Climate::SeriesColors`**

`app/services/climate/series_colors.rb`:

```ruby
module Climate
  ##
  # Which palette slot a sensor's line gets.
  #
  # Colour follows the SENSOR, not its position in the selection, so
  # deactivating one must not repaint the others — and so a sensor is the same
  # colour on every chart on the page, which is what lets them be read
  # together. Ranking by id across ALL sensors is stable under exactly the
  # operation that filters those lists.
  class SeriesColors
    def initialize
      @ids = Sensor.order(:id).pluck(:id)
    end

    def index_for(sensor) = @ids.index(sensor.id) || 0
  end
end
```

- [ ] **Step 6: Rewrite `SeriesQuery` to use them**

Replace `app/services/climate/series_query.rb` with:

```ruby
module Climate
  ##
  # The chart payload: one series per sensor, bucketed to suit the span.
  #
  # A year of ten-minute readings is 52,560 points per sensor; bucketing takes
  # that to 365, which is what keeps the payload small enough to embed in the
  # HTML rather than fetch.
  class SeriesQuery
    MEASURES = { temperature: "temperature_c", humidity: "relative_humidity",
                 dew_point: "dew_point_c" }.freeze

    POINT_KEYS = MEASURES.keys.flat_map { |m| [ m, :"#{m}_min", :"#{m}_max" ] }.freeze

    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
      @buckets = Buckets.new(range)
      @colors = SeriesColors.new
    end

    def bucket_seconds = @buckets.seconds
    def aggregated? = @buckets.aggregated?

    # -> [{ id:, name:, location:, placement:, outdoor:, color_index:,
    #       points: [{ t: iso8601, temperature:, temperature_min:,
    #                  temperature_max:, humidity:, …, dew_point:, … }] }]
    def series
      grouped = bucketed_rows

      @sensors.map do |sensor|
        { id: sensor.id, name: sensor.display_name, location: sensor.location,
          placement: sensor.placement, outdoor: sensor.outdoor?,
          color_index: @colors.index_for(sensor),
          points: @buckets.with_gaps(grouped.fetch(sensor.id, []), keys: POINT_KEYS) }
      end
    end

    private

    # AVG for the line, MIN/MAX for the spread band. Once a bucket is wider
    # than one reading the mean hides the extremes, and the extreme is what
    # condenses on a wall.
    def aggregates
      MEASURES.values.flat_map do |column|
        [ Arel.sql("AVG(#{column})"), Arel.sql("MIN(#{column})"), Arel.sql("MAX(#{column})") ]
      end
    end

    def bucketed_rows
      return {} if @sensors.empty?

      expression = @buckets.expression

      rows = Reading
             .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
             .group(:sensor_id, Arel.sql(expression))
             .order(Arel.sql("1 ASC, 2 ASC"))
             .pluck(:sensor_id, Arel.sql(expression), *aggregates)

      rows.group_by(&:first).transform_values { |sensor_rows| sensor_rows.map { |row| point(row) } }
    end

    def point(row)
      _sensor_id, bucket, *values = row

      MEASURES.keys.each_with_index.each_with_object({ t: @buckets.to_time(bucket) }) do |(measure, index), result|
        mean, minimum, maximum = values[index * 3, 3]
        result[measure] = round(mean)
        result[:"#{measure}_min"] = round(minimum)
        result[:"#{measure}_max"] = round(maximum)
      end
    end

    def round(value) = value&.to_f&.round(2)
  end
end
```

- [ ] **Step 7: Run the whole climate suite**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate test/models/climate test/jobs/climate test/functional/admin/climate
```
Expected: PASS, including `series_query_test.rb` **unmodified** — that file is the proof the refactor changed nothing observable.

- [ ] **Step 8: Add the min/max assertion to `SeriesQuery`'s tests**

Append to `test/services/climate/series_query_test.rb` (inside the existing class):

```ruby
  test "each point carries the spread as well as the mean" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 10.0, relative_humidity: 80.0, dew_point_c: 7.0)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                           temperature_c: 14.0, relative_humidity: 80.0, dew_point_c: 7.0)

    point = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points].first

    assert_in_delta 12.0, point[:temperature], 0.001
    assert_in_delta 10.0, point[:temperature_min], 0.001
    assert_in_delta 14.0, point[:temperature_max], 0.001
  end

  test "reports whether the buckets are wide enough for a spread to mean anything" do
    assert_not_predicate Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-08-05", to: "2026-08-06")), :aggregated?
    assert_predicate Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-07-25", to: "2026-08-06")), :aggregated?
  end
```

- [ ] **Step 9: Run and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate
git add app/services/climate test/services/climate
git commit -m "refactor(climate): share bucketing and colours across chart payloads

$(cat <<'MSG'
Three more chart payloads are coming and each needs the same bucket widths,
the same timezone-independent SQL and the same sensor-to-colour rule. A
margin line bucketed differently from the temperature line above it would be
unreadable next to it, so this becomes one rule rather than four copies.

Also plucks MIN/MAX alongside AVG: once a bucket is wider than one reading
the mean hides the extremes, and the extreme is what condenses on a wall.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 3: `Climate::CONDENSATION_RISK_MARGIN` and `Climate::MarginSeries`

**Files:**
- Modify: `app/models/climate.rb`, `app/helpers/climate_helper.rb`, `app/views/admin/climate/dashboard/show.html.erb:5`, `app/models/climate/reading.rb:44`
- Create: `app/services/climate/margin_series.rb`
- Test: `test/services/climate/margin_series_test.rb`

**Interfaces:**
- Consumes: `Climate::Buckets`, `Climate::SeriesColors`.
- Produces: `Climate::CONDENSATION_RISK_MARGIN` (Float `3.0`); `Climate::MarginSeries.new(sensors:, range:)` → `#series` → `[{ id: Integer, name: String, color_index: Integer, points: [{ t: String, margin: Float | nil }] }]`, and `#bucket_seconds`.

- [ ] **Step 1: Move the threshold onto the `Climate` module**

In `app/models/climate.rb`, after the `table_name_prefix` method:

```ruby
  # Below this many degrees between the air temperature and its dew point,
  # condensation is a live risk rather than a theoretical one. This is the
  # number the crypt monitor exists to watch — roughly 80% humidity at the
  # surface, which is where mould starts to grow.
  #
  # Lives here rather than in ClimateHelper because the risk services read it
  # too, and a service reaching into a view helper is the wrong direction.
  CONDENSATION_RISK_MARGIN = 3.0
```

In `app/helpers/climate_helper.rb`, delete the constant and its comment, and point the predicate at the moved one:

```ruby
  def climate_condensation_risk?(margin)
    margin.present? && margin < Climate::CONDENSATION_RISK_MARGIN
  end
```

In `app/views/admin/climate/dashboard/show.html.erb` line 5, replace `ClimateHelper::CONDENSATION_RISK_MARGIN` with `Climate::CONDENSATION_RISK_MARGIN`.

In `app/models/climate/reading.rb` line 44, update the comment reference to `See Climate::CONDENSATION_RISK_MARGIN.`

- [ ] **Step 2: Confirm no reference is left behind**

```bash
rg -n "ClimateHelper::CONDENSATION_RISK_MARGIN" --glob '!plans/**'
```
Expected: no output. (`plans/off-topic-improvements.md` mentions it in prose; leave that alone.)

- [ ] **Step 3: Write the failing `MarginSeries` tests**

`test/services/climate/margin_series_test.rb`:

```ruby
require "test_helper"

class Climate::MarginSeriesTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  def range(from:, to:)
    Climate::DateRange.from_params({ from: from, to: to })
  end

  def series_for(sensors, from:, to:)
    Climate::MarginSeries.new(sensors: Array(sensors), range: range(from: from, to: to)).series
  end

  # The whole reason this service exists. MIN(temp) - MAX(dew) takes its two
  # figures from different instants and invents a crypt that never existed.
  test "takes the worst margin in a bucket, not the coldest temperature against the wettest dew point" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 9.0) # margin 3.0
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                           temperature_c: 10.0, dew_point_c: 5.0) # margin 5.0

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_equal 1, points.size
    # MIN(temp) - MAX(dew) would be 10.0 - 9.0 = 1.0.
    assert_in_delta 3.0, points.first[:margin], 0.001
  end

  test "returns one series per sensor even when a sensor has no readings" do
    with_data = create_climate_sensor(display_name: "North", in_crypt: true)
    without = create_climate_sensor(display_name: "South", in_crypt: true)
    create_climate_reading(sensor: with_data, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    result = series_for([ with_data, without ], from: "2026-08-05", to: "2026-08-06")

    assert_equal 2, result.size
    assert_empty result.last[:points]
  end

  test "carries the sensor's own colour index" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    expected = Climate::SeriesColors.new.index_for(sensor)

    assert_equal expected, series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:color_index]
  end

  test "breaks the line across a gap rather than drawing through it" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 20:00"))

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_equal 3, points.size
    assert_nil points[1][:margin]
  end

  test "skips a reading with no dew point rather than treating it as zero" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 9.0)
    Climate::Reading.create!(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                             temperature_c: 12.0, relative_humidity: nil, dew_point_c: nil)

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_in_delta 3.0, points.first[:margin], 0.001
  end

  test "returns nothing when no sensor is marked as being in the crypt" do
    assert_empty series_for([], from: "2026-08-05", to: "2026-08-06")
  end
end
```

- [ ] **Step 4: Run to verify they fail**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/margin_series_test.rb
```
Expected: FAIL — `uninitialized constant Climate::MarginSeries`.

- [ ] **Step 5: Write `Climate::MarginSeries`**

`app/services/climate/margin_series.rb`:

```ruby
module Climate
  ##
  # The condensation-risk line: how far the crypt's air sat from its own dew
  # point, and how close that ever came to zero.
  #
  # The aggregate is MIN(temperature_c - dew_point_c) — the margin per row,
  # then the worst of them. NOT MIN(temperature_c) - MAX(dew_point_c), which
  # takes its two figures from different instants and invents a colder, wetter
  # crypt than ever existed. And not AVG: condensation is a worst-case event,
  # so a daily mean can sit comfortably at 5 °C while every night touched 1.
  #
  # Measured against the AIR, not the walls. The walls are underground and
  # colder, so the real margin at the stone is smaller than this line.
  class MarginSeries
    MARGIN = "temperature_c - dew_point_c".freeze

    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
      @buckets = Buckets.new(range)
      @colors = SeriesColors.new
    end

    def bucket_seconds = @buckets.seconds

    # -> [{ id:, name:, color_index:, points: [{ t: iso8601, margin: }] }]
    def series
      grouped = bucketed_rows

      @sensors.map do |sensor|
        { id: sensor.id, name: sensor.display_name,
          color_index: @colors.index_for(sensor),
          points: @buckets.with_gaps(grouped.fetch(sensor.id, []), keys: [ :margin ]) }
      end
    end

    private

    def bucketed_rows
      return {} if @sensors.empty?

      expression = @buckets.expression

      rows = Reading
             .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
             .where.not(temperature_c: nil).where.not(dew_point_c: nil)
             .group(:sensor_id, Arel.sql(expression))
             .order(Arel.sql("1 ASC, 2 ASC"))
             .pluck(:sensor_id, Arel.sql(expression), Arel.sql("MIN(#{MARGIN})"))

      rows.group_by(&:first).transform_values do |sensor_rows|
        sensor_rows.map do |(_sensor_id, bucket, margin)|
          { t: @buckets.to_time(bucket), margin: margin&.to_f&.round(2) }
        end
      end
    end
  end
end
```

- [ ] **Step 6: Run and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate test/models/climate
git add app/models/climate.rb app/helpers/climate_helper.rb app/models/climate/reading.rb \
        app/views/admin/climate/dashboard/show.html.erb \
        app/services/climate/margin_series.rb test/services/climate/margin_series_test.rb
git commit -m "feat(climate): plot the worst dew point margin per bucket

$(cat <<'MSG'
The margin between the crypt's air and its dew point is the number the
monitor exists to watch, and it only existed as an instantaneous figure on a
tile. Aggregates with MIN(temperature_c - dew_point_c) rather than the mean,
because condensation is a worst-case event: a daily average can sit at 5 °C
while every night touched 1.

Moves the threshold onto the Climate module, since the risk services need it
and a service reaching into a view helper is the wrong direction.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 4: `Climate::RiskSummary`

**Files:**
- Create: `app/services/climate/risk_summary.rb`
- Test: `test/services/climate/risk_summary_test.rb`

**Interfaces:**
- Consumes: `Climate::CONDENSATION_RISK_MARGIN`.
- Produces: `Climate::RiskSummary.new(sensors:, range:, threshold: Climate::CONDENSATION_RISK_MARGIN)` → `#summaries` → `[{ id: Integer, name: String, hours_with_readings: Integer, hours_at_risk: Integer, longest_spell_hours: Integer, longest_spell_ended_at: ActiveSupport::TimeWithZone | nil, days: [{ date: Date, hours_with_readings: Integer, at_risk_hours: Integer }] }]`.

- [ ] **Step 1: Write the failing tests**

`test/services/climate/risk_summary_test.rb`:

```ruby
require "test_helper"

class Climate::RiskSummaryTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Margin 1.0 — under the 3.0 threshold.
  def at_risk_reading(sensor, at)
    create_climate_reading(sensor: sensor, recorded_at: at, temperature_c: 12.0, dew_point_c: 11.0)
  end

  # Margin 6.0 — comfortably clear.
  def safe_reading(sensor, at)
    create_climate_reading(sensor: sensor, recorded_at: at, temperature_c: 12.0, dew_point_c: 6.0)
  end

  def summary_for(sensor, from:, to:)
    range = Climate::DateRange.from_params({ from: from, to: to })
    Climate::RiskSummary.new(sensors: [ sensor ], range: range).summaries.first
  end

  # "41 of 720 hours" reads as 6% of a month when it may be 8% of the six days
  # the hand-synced sensor actually covered.
  test "counts hours that have readings, not hours in the range" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    3.times { |offset| at_risk_reading(sensor, base + offset.hours) }

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 3, summary[:hours_with_readings]
    assert_equal 3, summary[:hours_at_risk]
  end

  test "several readings inside one hour count as one hour" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    [ 0, 10, 20, 30, 40, 50 ].each { |minutes| at_risk_reading(sensor, base + minutes.minutes) }

    assert_equal 1, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_with_readings]
  end

  test "an hour counts as at risk when its worst reading dips under the threshold" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    safe_reading(sensor, base)
    at_risk_reading(sensor, base + 30.minutes)

    assert_equal 1, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_at_risk]
  end

  test "a margin exactly on the threshold is not at risk" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 00:00"),
                           temperature_c: 12.0, dew_point_c: 9.0) # margin exactly 3.0

    assert_equal 0, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_at_risk]
  end

  # Readings arrive by hand-synced CSV, so multi-day holes are normal. Joining
  # across one would claim an unbroken damp spell that nothing measured.
  test "a gap in coverage breaks the longest spell" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    [ 0, 1, 3, 4, 5 ].each { |offset| at_risk_reading(sensor, base + offset.hours) }

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 5, summary[:hours_at_risk]
    assert_equal 3, summary[:longest_spell_hours]
  end

  test "a safe hour also breaks the spell" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    at_risk_reading(sensor, base)
    at_risk_reading(sensor, base + 1.hour)
    safe_reading(sensor, base + 2.hours)
    at_risk_reading(sensor, base + 3.hours)

    assert_equal 2, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:longest_spell_hours]
  end

  test "reports when the longest spell ended" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    at_risk_reading(sensor, base)
    at_risk_reading(sensor, base + 1.hour)

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal base + 2.hours, summary[:longest_spell_ended_at]
  end

  test "the per-day figures sum to the headline figure" do
    sensor = create_climate_sensor(in_crypt: true)
    at_risk_reading(sensor, Time.zone.parse("2026-08-04 22:00"))
    at_risk_reading(sensor, Time.zone.parse("2026-08-05 01:00"))
    at_risk_reading(sensor, Time.zone.parse("2026-08-05 02:00"))
    safe_reading(sensor, Time.zone.parse("2026-08-06 02:00"))

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 3, summary[:days].size
    assert_equal summary[:hours_at_risk], summary[:days].sum { |day| day[:at_risk_hours] }
    assert_equal summary[:hours_with_readings], summary[:days].sum { |day| day[:hours_with_readings] }
  end

  test "a sensor with no readings reports zeroes rather than nil" do
    sensor = create_climate_sensor(in_crypt: true)

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 0, summary[:hours_with_readings]
    assert_equal 0, summary[:hours_at_risk]
    assert_equal 0, summary[:longest_spell_hours]
    assert_nil summary[:longest_spell_ended_at]
    assert_empty summary[:days]
  end

  test "keeps each sensor's figures separate" do
    north = create_climate_sensor(display_name: "North", in_crypt: true)
    south = create_climate_sensor(display_name: "South", in_crypt: true)
    at_risk_reading(north, Time.zone.parse("2026-08-05 00:00"))
    safe_reading(south, Time.zone.parse("2026-08-05 00:00"))

    range = Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-07" })
    summaries = Climate::RiskSummary.new(sensors: [ north, south ], range: range).summaries

    assert_equal 1, summaries.first[:hours_at_risk]
    assert_equal 0, summaries.last[:hours_at_risk]
  end
end
```

- [ ] **Step 2: Run to verify they fail**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/risk_summary_test.rb
```
Expected: FAIL — `uninitialized constant Climate::RiskSummary`.

- [ ] **Step 3: Write `Climate::RiskSummary`**

`app/services/climate/risk_summary.rb`:

```ruby
module Climate
  ##
  # How much of the range the crypt spent close to condensing.
  #
  # Mould is a function of how LONG the air sat near saturation, not of how low
  # the margin ever got, so the unit here is the hour: hourly buckets, each
  # taking the worst margin inside it, counted three ways — total hours at
  # risk, the longest unbroken spell, and a per-day tally for the bars.
  #
  # The denominator is hours that HAVE readings, never hours in the range. The
  # sensors are hand-synced over Bluetooth and routinely miss days, so
  # "41 of 720 hours" reads as 6% of a month when it may be 8% of the six days
  # actually covered.
  class RiskSummary
    HOUR = 3_600
    BUCKET = "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)".freeze
    MARGIN = "temperature_c - dew_point_c".freeze

    def initialize(sensors:, range:, threshold: Climate::CONDENSATION_RISK_MARGIN)
      @sensors = Array(sensors)
      @range = range
      @threshold = threshold
    end

    # -> [{ id:, name:, hours_with_readings:, hours_at_risk:,
    #       longest_spell_hours:, longest_spell_ended_at:,
    #       days: [{ date:, hours_with_readings:, at_risk_hours: }] }]
    def summaries
      grouped = hourly_margins

      @sensors.map { |sensor| summarise(sensor, grouped.fetch(sensor.id, [])) }
    end

    private

    # One query for every sensor and every figure below: the three counts and
    # the bars all have to agree, so they all come off the same rows.
    def hourly_margins
      return {} if @sensors.empty?

      Reading
        .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
        .where.not(temperature_c: nil).where.not(dew_point_c: nil)
        .group(:sensor_id, Arel.sql(BUCKET))
        .order(Arel.sql("1 ASC, 2 ASC"))
        .pluck(:sensor_id, Arel.sql(BUCKET), Arel.sql("MIN(#{MARGIN})"))
        .group_by(&:first)
        .transform_values do |rows|
          rows.map { |(_sensor_id, hour, margin)| [ hour.in_time_zone, margin.to_f ] }
        end
    end

    def summarise(sensor, hours)
      spell = longest_spell(hours)

      { id: sensor.id, name: sensor.display_name,
        hours_with_readings: hours.size,
        hours_at_risk: hours.count { |(_hour, margin)| at_risk?(margin) },
        longest_spell_hours: spell[:hours],
        longest_spell_ended_at: spell[:ended_at],
        days: by_day(hours) }
    end

    def at_risk?(margin) = margin < @threshold

    # A missing hour BREAKS the run, the same way SeriesQuery refuses to draw a
    # line across an outage. Claiming thirty unbroken damp hours across a
    # twenty-hour hole is a measurement that never happened.
    def longest_spell(hours)
      best = { hours: 0, ended_at: nil }
      run = 0
      previous = nil

      hours.each do |(hour, margin)|
        run = if !at_risk?(margin)
                0
              elsif previous && (hour - previous) == HOUR && run.positive?
                run + 1
              else
                1
              end
        best = { hours: run, ended_at: hour + HOUR } if run > best[:hours]
        previous = hour
      end

      best
    end

    def by_day(hours)
      hours.group_by { |(hour, _margin)| hour.to_date }.map do |date, day_hours|
        { date: date,
          hours_with_readings: day_hours.size,
          at_risk_hours: day_hours.count { |(_hour, margin)| at_risk?(margin) } }
      end
    end
  end
end
```

- [ ] **Step 4: Run and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/risk_summary_test.rb
git add app/services/climate/risk_summary.rb test/services/climate/risk_summary_test.rb
git commit -m "feat(climate): count how long the crypt sat near condensing

$(cat <<'MSG'
Mould is a function of how long the air stayed near saturation, not of how
low the margin ever got, so the unit is the hour. Counts against hours that
have readings rather than hours in the range: the sensors are hand-synced and
routinely miss days, so a range denominator would report 6% of a month when
it means 8% of the six days covered. A coverage gap breaks a spell.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 5: `Climate::VentilationSeries`

**Files:**
- Create: `app/services/climate/ventilation_series.rb`
- Test: `test/services/climate/ventilation_series_test.rb`

**Interfaces:**
- Consumes: `Climate::SeriesQuery#series`, `Climate::SeriesColors`.
- Produces: `Climate::VentilationSeries.new(crypt_sensors:, outdoor_sensor:, range:, selected: nil)` with:
  - `WORST` = `"worst"`
  - `#options` → `[[String label, String value], …]`
  - `#selected_key` → String
  - `#sensor` → `Climate::Sensor | nil`
  - `#notice` → String | nil
  - `#series` → `[{ key: String, label: String, style: String, color_index: Integer, points: [{ t: String, value: Float | nil }] }]`, where `style` is one of `"solid"`, `"muted"`, `"dashed"`.

- [ ] **Step 1: Write the failing tests**

`test/services/climate/ventilation_series_test.rb`:

```ruby
require "test_helper"

class Climate::VentilationSeriesTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  def build(crypt, selected: nil, from: "2026-08-01", to: "2026-08-07", outdoor: @outdoor)
    Climate::VentilationSeries.new(
      crypt_sensors: Array(crypt), outdoor_sensor: outdoor,
      range: Climate::DateRange.from_params({ from: from, to: to }), selected: selected
    )
  end

  setup { @outdoor = outdoor_climate_sensor }

  test "picks the coldest crypt sensor by default" do
    warm = create_climate_sensor(display_name: "Warm", in_crypt: true)
    cold = create_climate_sensor(display_name: "Cold", in_crypt: true)
    create_climate_reading(sensor: warm, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 16.0)
    create_climate_reading(sensor: cold, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 9.0)

    assert_equal cold, build([ warm, cold ]).sensor
  end

  test "an explicit selection wins over the coldest" do
    warm = create_climate_sensor(display_name: "Warm", in_crypt: true)
    cold = create_climate_sensor(display_name: "Cold", in_crypt: true)
    create_climate_reading(sensor: warm, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 16.0)
    create_climate_reading(sensor: cold, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 9.0)

    subject = build([ warm, cold ], selected: warm.id.to_s)

    assert_equal warm, subject.sensor
    assert_nil subject.notice
    assert_equal warm.id.to_s, subject.selected_key
  end

  # DateRange clamps loudly rather than silently rendering something other
  # than what was asked for; this follows it.
  test "a sensor that is not in the crypt falls back and says so" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    elsewhere = create_climate_sensor(display_name: "Dressing room", in_crypt: false)

    subject = build([ crypt ], selected: elsewhere.id.to_s)

    assert_equal crypt, subject.sensor
    assert subject.notice.present?
  end

  test "an unparseable selection falls back and says so" do
    crypt = create_climate_sensor(in_crypt: true)

    subject = build([ crypt ], selected: "haddock")

    assert_equal crypt, subject.sensor
    assert subject.notice.present?
  end

  test "the worst-case key is reported as worst, not as the resolved sensor" do
    crypt = create_climate_sensor(in_crypt: true)

    assert_equal Climate::VentilationSeries::WORST, build([ crypt ]).selected_key
  end

  test "draws crypt temperature, crypt dew point and outdoor dew point" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 10.0)
    create_climate_reading(sensor: @outdoor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 18.0, dew_point_c: 6.0)

    series = build([ crypt ]).series

    assert_equal %w[crypt_temperature crypt_dew_point outdoor_dew_point], series.map { |line| line[:key] }
    assert_in_delta 12.0, series[0][:points].first[:value], 0.001
    assert_in_delta 10.0, series[1][:points].first[:value], 0.001
    assert_in_delta 6.0, series[2][:points].first[:value], 0.001
  end

  test "the outdoor line is styled apart from the crypt ones" do
    crypt = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"))
    create_climate_reading(sensor: @outdoor, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    assert_equal %w[solid muted dashed], build([ crypt ]).series.map { |line| line[:style] }
  end

  test "draws the crypt on its own when there is no outdoor feed" do
    crypt = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    series = build([ crypt ], outdoor: nil).series

    assert_equal %w[crypt_temperature crypt_dew_point], series.map { |line| line[:key] }
  end

  test "returns nothing when no sensor is marked as being in the crypt" do
    subject = build([])

    assert_nil subject.sensor
    assert_empty subject.series
  end

  test "offers the worst case plus every crypt sensor" do
    north = create_climate_sensor(display_name: "North", in_crypt: true)
    south = create_climate_sensor(display_name: "South", in_crypt: true)

    options = build([ north, south ]).options

    assert_equal [ Climate::VentilationSeries::WORST, north.id.to_s, south.id.to_s ],
                 options.map(&:last)
  end
end
```

- [ ] **Step 2: Run to verify they fail**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/ventilation_series_test.rb
```
Expected: FAIL — `uninitialized constant Climate::VentilationSeries`.

- [ ] **Step 3: Write `Climate::VentilationSeries`**

`app/services/climate/ventilation_series.rb`:

```ruby
module Climate
  ##
  # "Should I open the doors?" — the crypt's temperature and dew point against
  # the outside air's dew point, all in °C on one axis.
  #
  # Two readings from one chart. Outdoor dew point ABOVE the crypt's
  # temperature means the incoming air condenses on the stone however dry it
  # feels out there. Outdoor dew point BELOW the crypt's dew point means the
  # air is drier in absolute terms, so opening up dries the place out.
  # Relative humidity cannot be compared between two places at different
  # temperatures; dew point can, which is why all three lines are °C.
  #
  # A projection over SeriesQuery rather than new SQL: these are the numbers
  # the history charts already fetch, relabelled onto one axis. So the
  # aggregate is AVG, deliberately — this chart is read for the present, where
  # the buckets are raw anyway, and MarginSeries owns the historical worst case.
  class VentilationSeries
    WORST = "worst".freeze
    NOT_IN_CRYPT = "That sensor is not marked as being in the crypt, so the coldest one is shown instead.".freeze

    def initialize(crypt_sensors:, outdoor_sensor:, range:, selected: nil)
      @crypt_sensors = Array(crypt_sensors)
      @outdoor_sensor = outdoor_sensor
      @range = range
      @selected = selected.presence
    end

    def options
      [ [ "Coldest crypt sensor", WORST ] ] +
        @crypt_sensors.map { |sensor| [ sensor.display_name, sensor.id.to_s ] }
    end

    def sensor = resolved[:sensor]
    def notice = resolved[:notice]

    # WORST is reported back as WORST, not as the sensor it resolved to, so the
    # selection keeps meaning "whichever is coldest" as the range changes.
    def selected_key = resolved[:key]

    # -> [{ key:, label:, style:, color_index:, points: [{ t:, value: }] }]
    def series
      return [] if sensor.nil?

      raw = SeriesQuery.new(sensors: [ sensor, @outdoor_sensor ].compact, range: @range).series
      crypt = raw.find { |line| line[:id] == sensor.id }
      outdoor = @outdoor_sensor && raw.find { |line| line[:id] == @outdoor_sensor.id }

      [
        line("crypt_temperature", "#{sensor.display_name} temperature", crypt, :temperature, "solid"),
        line("crypt_dew_point", "#{sensor.display_name} dew point", crypt, :dew_point, "muted"),
        outdoor && line("outdoor_dew_point", "Outside dew point", outdoor, :dew_point, "dashed")
      ].compact
    end

    private

    def line(key, label, source, measure, style)
      { key: key, label: label, style: style, color_index: source[:color_index],
        points: source[:points].map { |point| { t: point[:t], value: point[measure] } } }
    end

    def resolved
      @resolved ||= resolve
    end

    def resolve
      return { sensor: nil, notice: nil, key: WORST } if @crypt_sensors.empty?
      return { sensor: coldest, notice: nil, key: WORST } if @selected.nil? || @selected == WORST

      chosen = @crypt_sensors.find { |sensor| sensor.id.to_s == @selected }
      return { sensor: chosen, notice: nil, key: chosen.id.to_s } if chosen

      { sensor: coldest, notice: NOT_IN_CRYPT, key: WORST }
    end

    # The coldest spot is where condensation happens. Resolved once from the
    # LOWEST MEAN temperature over the whole range rather than point by point,
    # so both crypt lines come from the same sensor: a chart whose temperature
    # and dew point came from different sensors could not be read for the gap
    # between them, and that gap is the first thing anyone reads.
    def coldest
      means = Reading
              .where(sensor_id: @crypt_sensors.map(&:id),
                     recorded_at: @range.starts_at..@range.ends_at)
              .group(:sensor_id)
              .average(:temperature_c)

      @crypt_sensors.min_by { |sensor| means[sensor.id] || Float::INFINITY }
    end
  end
end
```

- [ ] **Step 4: Run and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate
git add app/services/climate/ventilation_series.rb test/services/climate/ventilation_series_test.rb
git commit -m "feat(climate): compare outside dew point with the crypt on one axis

$(cat <<'MSG'
The How this works copy already tells people to compare the outside dew point
against the crypt's temperature. They could not: those lines lived on
different charts with different y-axes.

Worst case resolves to the single coldest crypt sensor rather than a
composite of the lowest temperature and highest dew point across sensors. A
chart whose two lines came from different sensors cannot be read for the gap
between them, and that gap is the first thing anyone reads.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 6: Controller, payloads and URL state

**Files:**
- Modify: `app/controllers/admin/climate/dashboard_controller.rb`
- Modify: `app/helpers/climate_helper.rb`
- Test: `test/functional/admin/climate/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `MarginSeries`, `RiskSummary`, `VentilationSeries`, `SeriesQuery#aggregated?`.
- Produces, for the views: `@sensors`, `@crypt_sensors`, `@outdoor_sensor`, `@range`, `@series`, `@banded` (Boolean), `@margin_series`, `@risk`, `@ventilation` (a `Climate::VentilationSeries`). Helper `climate_link_params(range_params, selected_key)` → Hash.

- [ ] **Step 1: Write the failing controller tests**

Append to `test/functional/admin/climate/dashboard_controller_test.rb` (inside the existing class):

```ruby
      test "the json payload carries the margin, risk and ventilation series" do
        sensor = create_climate_sensor(in_crypt: true)
        outdoor_climate_sensor
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show, format: :json
        payload = response.parsed_body

        assert payload.key?("margin")
        assert payload.key?("risk")
        assert payload.key?("ventilation")
        assert_equal "worst", payload.dig("ventilation", "selected")
      end

      test "the crypt parameter selects which sensor the ventilation chart shows" do
        north = create_climate_sensor(display_name: "North", in_crypt: true)
        south = create_climate_sensor(display_name: "South", in_crypt: true)
        create_climate_reading(sensor: north, recorded_at: 2.hours.ago, temperature_c: 9.0)
        create_climate_reading(sensor: south, recorded_at: 2.hours.ago, temperature_c: 16.0)

        get :show, format: :json, params: { crypt: south.id.to_s }

        assert_equal south.id.to_s, response.parsed_body.dig("ventilation", "selected")
      end

      test "an unknown crypt parameter falls back and says so" do
        create_climate_sensor(in_crypt: true)

        get :show, params: { crypt: "haddock" }

        assert_response :success
        assert flash.now[:notice].present?
      end

      test "renders with no sensor marked as being in the crypt" do
        create_climate_sensor(in_crypt: false)

        get :show

        assert_response :success
      end

      test "renders with a crypt sensor that has no readings" do
        create_climate_sensor(in_crypt: true)

        get :show

        assert_response :success
      end
```

- [ ] **Step 2: Run to verify they fail**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/functional/admin/climate/dashboard_controller_test.rb
```
Expected: FAIL — the payload has no `margin` key.

- [ ] **Step 3: Rewrite the controller action**

`app/controllers/admin/climate/dashboard_controller.rb`:

```ruby
module Admin
  module Climate
    ##
    # The dashboard: current-reading tiles, the condensation-risk view (margin
    # chart, at-risk figures, per-day bars), the ventilation comparison, and
    # the three raw history charts.
    #
    # Answer first, evidence second — the derived views are what somebody
    # actually needs, and the raw lines are there to check them against.
    class DashboardController < BaseController
      def show
        @title = "Crypt Climate"
        @sensors = ::Climate::Sensor.active.in_display_order.to_a
        @crypt_sensors = @sensors.select(&:in_crypt?)
        @outdoor_sensor = @sensors.find(&:outdoor?)
        @range = ::Climate::DateRange.from_params(params)

        build_series
        announce(@range.notice, @ventilation.notice)

        respond_to do |format|
          format.html
          # Served for the same data the page draws, so the charts can be
          # checked without reading pixels off a canvas.
          format.json { render json: payload }
        end
      end

      private

      def build_series
        query = ::Climate::SeriesQuery.new(sensors: @sensors, range: @range)
        @series = query.series
        # A min-max band means nothing until a bucket holds more than one
        # reading, and would draw as a zero-width artefact at raw resolution.
        @banded = query.aggregated?

        @margin_series = ::Climate::MarginSeries.new(sensors: @crypt_sensors, range: @range).series
        @risk = ::Climate::RiskSummary.new(sensors: @crypt_sensors, range: @range).summaries
        @ventilation = ::Climate::VentilationSeries.new(crypt_sensors: @crypt_sensors,
                                                        outdoor_sensor: @outdoor_sensor,
                                                        range: @range, selected: params[:crypt])
      end

      # Both fall back rather than fail, so both have to SAY they fell back.
      def announce(*notices)
        said = notices.compact_blank
        flash.now[:notice] = said.join(" ") if said.any?
      end

      def payload
        { range: @range.as_json, series: @series, banded: @banded,
          margin: @margin_series, risk: @risk,
          ventilation: { selected: @ventilation.selected_key, series: @ventilation.series } }
      end
    end
  end
end
```

- [ ] **Step 4: Add the link helper**

In `app/helpers/climate_helper.rb`, after `climate_range_presets`:

```ruby
  # Carries the ventilation selection through every link that changes the
  # range, so picking a sensor and then changing the dates does not silently
  # reset which sensor is on screen.
  #
  # The default is left OUT of the URL, the same way DateRange leaves the
  # default range out: a clean link keeps meaning "recent, coldest sensor".
  def climate_link_params(range_params, selected_key)
    return range_params if selected_key.blank? || selected_key == Climate::VentilationSeries::WORST

    range_params.merge(crypt: selected_key)
  end
```

- [ ] **Step 5: Carry the selection through the existing range controls**

In `app/views/admin/climate/dashboard/show.html.erb`, inside the `form_with` block, add a hidden field before the `:from` label:

```erb
    <%= hidden_field_tag :crypt, @ventilation.selected_key unless @ventilation.selected_key == Climate::VentilationSeries::WORST %>
```

and change the preset link to carry it:

```erb
        <%= link_to label, admin_climate_dashboard_path(climate_link_params(dates, @ventilation.selected_key)),
                    class: btn_classes(:secondary, :sm) %>
```

and the "View as data" link:

```erb
    <%= link_to "View as data",
                admin_climate_dashboard_path(climate_link_params(@range.to_param, @ventilation.selected_key).merge(format: :json)),
                class: btn_classes(:secondary, :sm) %>
```

- [ ] **Step 6: Run and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/functional/admin/climate
git add app/controllers/admin/climate/dashboard_controller.rb app/helpers/climate_helper.rb \
        app/views/admin/climate/dashboard/show.html.erb \
        test/functional/admin/climate/dashboard_controller_test.rb
git commit -m "feat(climate): serve the risk and ventilation payloads

$(cat <<'MSG'
Adds ?crypt= to the dashboard's URL state and carries it through the range
form, the presets and the data link, so picking a sensor and then changing
the dates does not silently reset which sensor is on screen. An unknown key
falls back to the coldest sensor and says so, as DateRange does for an
unusable range.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 7: Extract the shared chart library, add the spread band

**Files:**
- Create: `app/javascript/lib/climate_chart.js`
- Modify: `app/javascript/controllers/climate_charts_controller.js`
- Modify: `app/views/admin/climate/dashboard/show.html.erb`
- Test: `test/system/admin/climate/charts_js_test.rb`

**Interfaces:**
- Produces, from `app/javascript/lib/climate_chart.js`:
  - `PALETTE` (Array of hex strings)
  - `colorFor(index)` → String
  - `withAlpha(hex, alpha)` → String rgba
  - `loadChartJs({ bars = false })` → Promise of the `Chart` constructor, registered
  - `reducedMotion()` → Boolean
  - `endLabelPlugin()` → Chart.js plugin object
  - `timeScaleOptions({ title, unit })` → Object for `options.scales`
  - `legendAndTooltip({ unit })` → Object for `options.plugins`
  - `seriesAriaLabel({ title, unit, entries })` → String, where `entries` is `[{ name, values }]`

- [ ] **Step 1: Write the shared library**

`app/javascript/lib/climate_chart.js`:

```js
// Shared machinery for the climate dashboard's charts: the palette, the lazy
// Chart.js import, the end-of-line labels, and the axis/legend defaults.
//
// Extracted because there are four chart controllers on this page and jscpd
// gates duplication at zero — but also because a sensor has to be the same
// colour and the same shape on every one of them, or they cannot be read
// together.

// Fixed order, never cycled. Validated for the light surface: worst adjacent
// CVD ΔE 9.1, normal-vision ΔE 19.6. Three slots fall below 3:1 contrast,
// which is why every series also carries an end-of-line direct label.
export const PALETTE = [
  "#2a78d6", // blue
  "#eb6834", // orange
  "#1baf7a", // aqua
  "#eda100", // yellow
  "#e87ba4", // magenta
  "#008300", // green
  "#4a3aa7", // violet
  "#e34948", // red
]

export const AXIS_COLOR = "#52514e"
export const GRID_COLOR = "rgba(0,0,0,0.05)"

export function colorFor(index) {
  return PALETTE[index % PALETTE.length]
}

export function withAlpha(hex, alpha) {
  const value = parseInt(hex.slice(1), 16)
  return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`
}

export function reducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

// Chart.js is imported lazily, matching techie_graph_controller and
// map_controller, so no other admin page pays for it.
export async function loadChartJs({ bars = false } = {}) {
  const [chartjs] = await Promise.all([
    import("chart.js"),
    import("chartjs-adapter-date-fns"),
  ])
  const {
    Chart, LineController, LineElement, PointElement, BarController, BarElement,
    LinearScale, CategoryScale, TimeScale, Tooltip, Legend, Filler,
  } = chartjs

  Chart.register(LineController, LineElement, PointElement, LinearScale, TimeScale,
                 Tooltip, Legend, Filler)
  if (bars) Chart.register(BarController, BarElement, CategoryScale)

  return Chart
}

export function timeScaleOptions({ title, unit }) {
  return {
    x: {
      type: "time",
      time: { tooltipFormat: "d MMM yyyy HH:mm" },
      grid: { color: GRID_COLOR },
      ticks: { maxRotation: 0, autoSkipPadding: 24, color: AXIS_COLOR },
    },
    y: {
      title: { display: true, text: title, color: AXIS_COLOR },
      grid: { color: GRID_COLOR },
      ticks: { color: AXIS_COLOR, callback: (value) => `${value}${unit}` },
    },
  }
}

export function legendAndTooltip({ unit }) {
  return {
    legend: {
      position: "bottom",
      labels: {
        usePointStyle: true,
        color: "#0b0b0b",
        // Spread bands are scenery, not series. Listing them doubles the
        // legend and offers the reader a toggle that half-erases a chart.
        filter: (item, data) => !data.datasets[item.datasetIndex].band,
      },
    },
    tooltip: {
      filter: (item) => !item.dataset.band,
      callbacks: { label: (item) => `${item.dataset.label}: ${item.formattedValue}${unit}` },
    },
  }
}

// Required relief for the palette slots below 3:1 against the surface.
export function endLabelPlugin() {
  const FONT = "600 11px system-ui, sans-serif"
  const GAP = 6
  // Past this the labels eat the plot. Longer names are ellipsised instead.
  const MAX_WIDTH = 150

  const fit = (ctx, text) => {
    if (ctx.measureText(text).width <= MAX_WIDTH) return text

    let truncated = text
    while (truncated.length > 1 && ctx.measureText(`${truncated}…`).width > MAX_WIDTH) {
      truncated = truncated.slice(0, -1)
    }
    return `${truncated}…`
  }

  const visible = (chart, dataset, index) =>
    !dataset.band && !chart.getDatasetMeta(index).hidden

  return {
    id: "climateEndLabels",

    // Measured, not guessed: a fixed padding clips a longer sensor name.
    beforeLayout(chart) {
      const ctx = chart.ctx
      ctx.save()
      ctx.font = FONT
      const widest = chart.data.datasets.reduce(
        (max, dataset, index) =>
          visible(chart, dataset, index)
            ? Math.max(max, ctx.measureText(fit(ctx, dataset.label)).width)
            : max,
        0,
      )
      ctx.restore()
      chart.options.layout.padding.right = Math.ceil(widest) + GAP * 2
    },

    afterDatasetsDraw(chart) {
      const { ctx } = chart
      ctx.save()
      ctx.font = FONT
      ctx.textBaseline = "middle"

      chart.data.datasets.forEach((dataset, index) => {
        if (!visible(chart, dataset, index)) return

        const meta = chart.getDatasetMeta(index)
        const last = [...meta.data].reverse().find((point) => point && !Number.isNaN(point.y))
        if (!last) return

        ctx.fillStyle = dataset.borderColor
        ctx.fillText(fit(ctx, dataset.label), last.x + GAP, last.y)
      })
      ctx.restore()
    },
  }
}

export function seriesAriaLabel({ title, unit, entries, suffix }) {
  const parts = entries.map(({ name, values }) => {
    const present = values.filter((value) => value !== null && value !== undefined)
    if (present.length === 0) return `${name}: no readings`

    const min = Math.min(...present).toFixed(1)
    const max = Math.max(...present).toFixed(1)
    const latest = present[present.length - 1].toFixed(1)
    return `${name}: latest ${latest}${unit}, ranging ${min} to ${max}${unit}`
  })

  return `${title}. ${parts.join(". ")}. ${suffix}`
}
```

- [ ] **Step 2: Rewrite `climate_charts_controller.js` on top of it**

`app/javascript/controllers/climate_charts_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import {
  colorFor, withAlpha, endLabelPlugin, legendAndTooltip, loadChartJs,
  reducedMotion, seriesAriaLabel, timeScaleOptions,
} from "../lib/climate_chart"

// Three stacked time-series charts (temperature, relative humidity, dew point)
// over one shared x-axis, one line per sensor plus the outdoor comparison.
//
// Past two days the server widens the buckets and the mean starts hiding the
// extremes, so each line then also carries a shaded min-max band. The extreme
// is what condenses on a wall.
export default class extends Controller {
  static targets = ["temperature", "humidity", "dewPoint"]
  static values = { series: Array, banded: Boolean }

  #charts = []
  #syncing = false

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()

    // Turbo can disconnect us mid-import, onto detached canvases.
    if (!this.element.isConnected) return

    this.#charts = [
      this.#build(Chart, this.temperatureTarget, "temperature", "Temperature (°C)", "°C"),
      this.#build(Chart, this.humidityTarget, "humidity", "Relative humidity (%)", "%"),
      this.#build(Chart, this.dewPointTarget, "dew_point", "Dew point (°C)", "°C"),
    ].filter(Boolean)

    // Chart.js is an ES module, so there is no window.Chart. These are the
    // handles for checking what was actually plotted, from the browser tests
    // and from the console when a live page looks wrong.
    this.element.climateCharts = this.#charts
    this.element.dataset.climateChartsReady = String(this.#charts.length)
  }

  disconnect() {
    // Or every Turbo navigation back leaks a canvas and its listeners.
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateChartsReady
  }

  #datasets(measure) {
    return this.seriesValue.flatMap((series) => {
      const color = colorFor(series.color_index)
      const line = {
        label: series.name,
        // spanGaps stays false so the explicit null points the server inserts
        // BREAK the line across an outage rather than interpolating through it.
        spanGaps: false,
        data: series.points.map((point) => ({ x: point.t, y: point[measure] })),
        borderColor: color,
        backgroundColor: color,
        // Second cue for the outdoor line, so it reads apart without relying on hue.
        borderDash: series.outdoor ? [6, 4] : [],
        borderWidth: 2,
        pointRadius: 0,
        pointHoverRadius: 5,
        tension: 0.2,
      }

      return this.bandedValue ? [...this.#band(series, measure, color), line] : [line]
    })
  }

  // Drawn under the line, max first with fill pointing at the min below it.
  #band(series, measure, color) {
    const shared = {
      label: series.name,
      band: true,
      spanGaps: false,
      borderWidth: 0,
      pointRadius: 0,
      backgroundColor: withAlpha(color, 0.12),
    }

    return [
      { ...shared, fill: "+1", data: series.points.map((p) => ({ x: p.t, y: p[`${measure}_max`] })) },
      { ...shared, fill: false, data: series.points.map((p) => ({ x: p.t, y: p[`${measure}_min`] })) },
    ]
  }

  #build(Chart, canvas, measure, title, unit) {
    if (!canvas) return null

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit,
      entries: this.seriesValue.map((s) => ({ name: s.name, values: s.points.map((p) => p[measure]) })),
      suffix: "The current readings are also listed as text above this chart.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: { datasets: this.#datasets(measure) },
      plugins: [endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        interaction: { mode: "index", intersect: false },
        // Right padding is measured by the end-label plugin.
        layout: { padding: { right: 0 } },
        scales: timeScaleOptions({ title, unit }),
        plugins: legendAndTooltip({ unit }),
        onHover: (_event, elements, chart) => this.#syncHover(chart, elements),
      },
    })
  }

  // The point of stacking them is reading all three at the same instant.
  #syncHover(source, elements) {
    if (this.#syncing) return
    this.#syncing = true
    try {
      for (const chart of this.#charts) {
        if (chart === source) continue
        const mapped = elements.map((element) => ({
          datasetIndex: element.datasetIndex,
          index: element.index,
        }))
        chart.setActiveElements(mapped)
        chart.tooltip.setActiveElements(mapped, { x: 0, y: 0 })
        chart.update("none")
      }
    } finally {
      this.#syncing = false
    }
  }
}
```

- [ ] **Step 3: Pass the banded flag from the view**

In `app/views/admin/climate/dashboard/show.html.erb`, extend the controller div:

```erb
  <div data-controller="climate-charts"
       data-climate-charts-series-value="<%= @series.to_json %>"
       data-climate-charts-banded-value="<%= @banded %>">
```

- [ ] **Step 4: Add a system test for the band**

Append to `test/system/admin/climate/charts_js_test.rb` (inside the existing class):

```ruby
      test "draws a spread band once the buckets are wide enough to hide the extremes" do
        visit admin_climate_dashboard_path(from: 30.days.ago.to_date.iso8601, to: Date.current.iso8601)
        wait_for_charts

        bands = evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector("[data-controller='climate-charts']")
            return root.climateCharts[0].data.datasets.filter((d) => d.band).length
          })()
        JS

        assert_operator bands, :>, 0
      end

      test "leaves the raw view unbanded" do
        visit admin_climate_dashboard_path
        wait_for_charts

        bands = evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector("[data-controller='climate-charts']")
            return root.climateCharts[0].data.datasets.filter((d) => d.band).length
          })()
        JS

        assert_equal 0, bands
      end
```

- [ ] **Step 5: Verify in a browser**

Ensure `bin/dev` is running for this worktree (ask the user to start it if not — do not start one yourself). Then:

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test:system TEST=test/system/admin/climate/charts_js_test.rb
```
Expected: PASS, all tests including the pre-existing ones — the refactor must not change what the three charts plot.

**Note:** stop `bin/dev` before running system tests, per the known port collision.

- [ ] **Step 6: Lint and commit**

```bash
pnpm exec eslint app/javascript/lib/climate_chart.js app/javascript/controllers/climate_charts_controller.js
git add app/javascript/lib/climate_chart.js app/javascript/controllers/climate_charts_controller.js \
        app/views/admin/climate/dashboard/show.html.erb test/system/admin/climate/charts_js_test.rb
git commit -m "refactor(climate): share the chart machinery, band the spread

$(cat <<'MSG'
Three more chart controllers are coming and jscpd gates duplication at zero,
so the palette, the lazy Chart.js import, the end-of-line labels and the axis
defaults move to a library. A sensor also has to be the same colour and shape
on every chart, or they cannot be read together.

Past two days the server widens the buckets and the mean starts hiding the
extremes, so each line now carries a shaded min-max band. The extreme is what
condenses on a wall. Bands are excluded from the legend and tooltips: they
are scenery, not series.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 8: The condensation-risk card

**Files:**
- Create: `app/javascript/controllers/climate_margin_chart_controller.js`
- Create: `app/views/admin/climate/dashboard/_condensation_risk.html.erb`
- Create: `app/views/admin/climate/dashboard/_risk_figures.html.erb`
- Modify: `app/helpers/climate_helper.rb`
- Modify: `app/views/admin/climate/dashboard/show.html.erb`
- Test: `test/functional/admin/climate/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `@margin_series`, `@risk`, `@crypt_sensors`, `Climate::CONDENSATION_RISK_MARGIN`.
- Produces: helper `climate_risk_sentence(summary)` → String; Stimulus controller `climate-margin-chart` with `series` (Array) and `threshold` (Number) values, exposing `element.climateCharts` and `data-climate-margin-chart-ready`.

- [ ] **Step 1: Write the failing helper test**

Create `test/helpers/climate_helper_test.rb`:

```ruby
require "test_helper"

class ClimateHelperTest < ActionView::TestCase
  include ClimateHelper

  def summary(hours_with_readings:, hours_at_risk:, longest_spell_hours: 0, longest_spell_ended_at: nil)
    { id: 1, name: "Crypt", hours_with_readings: hours_with_readings,
      hours_at_risk: hours_at_risk, longest_spell_hours: longest_spell_hours,
      longest_spell_ended_at: longest_spell_ended_at, days: [] }
  end

  test "says so plainly when nothing came close" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 512, hours_at_risk: 0))

    assert_match(/512 hours with readings/, sentence)
    assert_match(/none/i, sentence)
  end

  # The denominator is hours with readings, never hours in the range.
  test "quotes the at-risk count against the hours that have readings" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 512, hours_at_risk: 41,
                                             longest_spell_hours: 14,
                                             longest_spell_ended_at: Time.zone.parse("2026-03-03 09:00")))

    assert_match(/41 of the 512 hours with readings/, sentence)
    assert_match(/8%/, sentence)
    assert_match(/longest unbroken spell was 14 hours/, sentence)
  end

  test "says there is nothing to report when the sensor has no readings" do
    assert_match(/No readings/i, climate_risk_sentence(summary(hours_with_readings: 0, hours_at_risk: 0)))
  end

  test "does not mention a spell when there was not one" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 10, hours_at_risk: 0))

    assert_no_match(/spell/, sentence)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/helpers/climate_helper_test.rb
```
Expected: FAIL — `undefined method 'climate_risk_sentence'`.

- [ ] **Step 3: Write the helper**

Append to `app/helpers/climate_helper.rb`:

```ruby
  # The at-risk figures as a sentence, because the question that matters must
  # not depend on a chart rendering — the same reason the Now tiles are HTML.
  #
  # The denominator is hours WITH READINGS. "41 of 720 hours" would read as 6%
  # of a month when the hand-synced sensor covered six days of it.
  def climate_risk_sentence(summary)
    return "No readings in this range." if summary[:hours_with_readings].zero?

    threshold = number_with_precision(Climate::CONDENSATION_RISK_MARGIN, precision: 1)
    covered = pluralize(summary[:hours_with_readings], "hour")

    return "None of the #{covered} with readings came under #{threshold} °C of margin." if summary[:hours_at_risk].zero?

    percentage = (100.0 * summary[:hours_at_risk] / summary[:hours_with_readings]).round
    [ "#{summary[:hours_at_risk]} of the #{covered} with readings (#{percentage}%) " \
      "were under #{threshold} °C of margin.",
      climate_spell_sentence(summary) ].compact_blank.join(" ")
  end

  def climate_spell_sentence(summary)
    return nil if summary[:longest_spell_hours].to_i.zero?

    ended = summary[:longest_spell_ended_at]
    "The longest unbroken spell was #{pluralize(summary[:longest_spell_hours], 'hour')}" \
      "#{", ending #{ended.strftime('%-d %B %Y, %H:%M')}" if ended}."
  end
```

Note: `strftime`, not `l(ended, format: :long)`. `config/locales/en.yml` defines `long` under
`date.formats` only (`'%A %d %B'`), so the `time.formats.long` lookup would miss.

- [ ] **Step 4: Run the helper test**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/helpers/climate_helper_test.rb
```
Expected: PASS.

- [ ] **Step 5: Write the margin chart controller**

`app/javascript/controllers/climate_margin_chart_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import {
  colorFor, endLabelPlugin, legendAndTooltip, loadChartJs, reducedMotion,
  seriesAriaLabel, timeScaleOptions,
} from "../lib/climate_chart"

// How close the crypt came to condensing: one line per crypt sensor, plotting
// the WORST margin in each bucket rather than the average, with everything
// under the threshold shaded.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { series: Array, threshold: Number }

  #charts = []

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateMarginChartReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateMarginChartReady
  }

  #build(Chart) {
    const canvas = this.canvasTarget
    const title = "Margin above dew point (°C)"

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit: "°C",
      entries: this.seriesValue.map((s) => ({ name: s.name, values: s.points.map((p) => p.margin) })),
      suffix: "The same figures are summarised as text above this chart.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: {
        datasets: this.seriesValue.map((series) => ({
          label: series.name,
          spanGaps: false,
          data: series.points.map((point) => ({ x: point.t, y: point.margin })),
          borderColor: colorFor(series.color_index),
          backgroundColor: colorFor(series.color_index),
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 5,
          tension: 0.2,
        })),
      },
      plugins: [this.#riskBandPlugin(), endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        interaction: { mode: "index", intersect: false },
        layout: { padding: { right: 0 } },
        scales: timeScaleOptions({ title, unit: "°C" }),
        plugins: legendAndTooltip({ unit: "°C" }),
      },
    })
  }

  // Drawn under the lines, so a night that dipped into the band is visible as
  // a line entering shaded ground rather than as a number to compare against.
  #riskBandPlugin() {
    const threshold = this.thresholdValue

    return {
      id: "climateRiskBand",
      beforeDatasetsDraw(chart) {
        const { ctx, chartArea, scales } = chart
        if (!chartArea) return

        const top = Math.max(scales.y.getPixelForValue(threshold), chartArea.top)
        if (top >= chartArea.bottom) return

        ctx.save()
        ctx.fillStyle = "rgba(227, 73, 72, 0.10)"
        ctx.fillRect(chartArea.left, top, chartArea.width, chartArea.bottom - top)
        ctx.strokeStyle = "rgba(227, 73, 72, 0.55)"
        ctx.setLineDash([4, 4])
        ctx.beginPath()
        ctx.moveTo(chartArea.left, top)
        ctx.lineTo(chartArea.right, top)
        ctx.stroke()
        ctx.restore()
      },
    }
  }
}
```

- [ ] **Step 6: Write the partials**

`app/views/admin/climate/dashboard/_risk_figures.html.erb`:

```erb
<%#
  The at-risk figures as text rather than pixels on a canvas, so the question
  that matters never depends on the chart rendering, and screen readers get it
  directly. Same reasoning as the Now tiles.
%>
<ul class="list-none pl-0 mb-4 space-y-1">
  <% summaries.each do |summary| %>
    <li class="text-sm">
      <strong><%= summary[:name] %>.</strong>
      <span class="<%= summary[:hours_at_risk].positive? ? 'text-red-700' : 'text-gray-600' %>">
        <%= climate_risk_sentence(summary) %>
      </span>
    </li>
  <% end %>
</ul>
```

`app/views/admin/climate/dashboard/_condensation_risk.html.erb`:

```erb
<%= render CardComponent.new(title: "Condensation risk", html_class: "mb-4") do %>
  <% if crypt_sensors.empty? %>
    <p class="text-gray-600 mb-0">
      No sensors are marked as being in the crypt.
      <%= link_to "Tick one on the sensor list", admin_climate_sensors_path, class: "text-primary underline" %>
      to see how close it came to condensing.
    </p>
  <% else %>
    <p class="mb-3 text-gray-600">
      How far the crypt's air stayed from its own dew point — the lower the line, the closer it
      came to condensing. Each point is the <strong>worst</strong> margin in its bucket, not the
      average, because condensation is a worst-case event. Measured against the air; the walls are
      colder, so the real margin at the stone is smaller than this.
    </p>

    <%= render "risk_figures", summaries: risk %>

    <% if margin_series.any? { |series| series[:points].any? } %>
      <div data-controller="climate-margin-chart"
           data-climate-margin-chart-series-value="<%= margin_series.to_json %>"
           data-climate-margin-chart-threshold-value="<%= Climate::CONDENSATION_RISK_MARGIN %>">
        <div class="relative h-64"><canvas data-climate-margin-chart-target="canvas"></canvas></div>
      </div>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 7: Render it from the dashboard**

In `app/views/admin/climate/dashboard/show.html.erb`, immediately after the `Now` card's `<% end %>` and before the `History` card:

```erb
<%= render "condensation_risk", crypt_sensors: @crypt_sensors, risk: @risk, margin_series: @margin_series %>
```

- [ ] **Step 8: Add rendering assertions**

Append to `test/functional/admin/climate/dashboard_controller_test.rb`:

```ruby
      test "shows the at-risk figures for a crypt sensor" do
        sensor = create_climate_sensor(display_name: "Crypt north", in_crypt: true)
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago,
                               temperature_c: 12.0, dew_point_c: 11.0)

        get :show

        assert_match(/Crypt north/, response.body)
        assert_match(/hours? with readings/, response.body)
      end

      test "prompts for a crypt sensor when none is ticked" do
        create_climate_sensor(in_crypt: false)

        get :show

        assert_match(/No sensors are marked as being in the crypt/, response.body)
      end
```

- [ ] **Step 9: Run, lint and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/functional/admin/climate test/helpers/climate_helper_test.rb
pnpm exec eslint app/javascript/controllers/climate_margin_chart_controller.js
bundle exec herb lint app/views/admin/climate/dashboard
git add app/javascript/controllers/climate_margin_chart_controller.js \
        app/views/admin/climate/dashboard app/helpers/climate_helper.rb \
        test/helpers/climate_helper_test.rb test/functional/admin/climate/dashboard_controller_test.rb
git commit -m "feat(climate): show how close the crypt came to condensing

$(cat <<'MSG'
The margin chart plots the worst point in each bucket with everything under
the threshold shaded, so a night that dipped reads as a line entering shaded
ground rather than a number to compare against.

The figures above it are HTML, not canvas: the question that matters must not
depend on the chart rendering, and screen readers get it directly.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 9: The per-day risk bars

**Files:**
- Create: `app/javascript/controllers/climate_risk_bars_controller.js`
- Modify: `app/views/admin/climate/dashboard/_condensation_risk.html.erb`

**Interfaces:**
- Consumes: `@risk` (each summary's `days` array), `app/javascript/lib/climate_chart.js`.
- Produces: Stimulus controller `climate-risk-bars` with a `summaries` (Array) value, exposing `element.climateCharts` and `data-climate-risk-bars-ready`.

- [ ] **Step 1: Write the controller**

`app/javascript/controllers/climate_risk_bars_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { AXIS_COLOR, GRID_COLOR, colorFor, loadChartJs, reducedMotion } from "../lib/climate_chart"

// Hours at risk per day, one bar group per crypt sensor. Mould is a function
// of how long the air sat near saturation, so a bad week has to be visible as
// a cluster rather than buried in a single total.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { summaries: Array }

  #charts = []

  async connect() {
    const labels = this.#labels()
    if (labels.length === 0) return

    const Chart = await loadChartJs({ bars: true })
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart, labels)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateRiskBarsReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateRiskBarsReady
  }

  // The union of every sensor's covered days, so a day one sensor missed
  // still lines up under the others rather than shifting them along.
  #labels() {
    const dates = new Set()
    this.summariesValue.forEach((summary) => summary.days.forEach((day) => dates.add(day.date)))
    return [...dates].sort()
  }

  #build(Chart, labels) {
    const canvas = this.canvasTarget

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", this.#ariaLabel())

    return new Chart(canvas, {
      type: "bar",
      data: {
        labels,
        datasets: this.summariesValue.map((summary) => {
          const byDate = new Map(summary.days.map((day) => [day.date, day.at_risk_hours]))
          return {
            label: summary.name,
            // A day the sensor did not cover is left null, not zero: zero
            // would read as "measured, and fine".
            data: labels.map((date) => (byDate.has(date) ? byDate.get(date) : null)),
            backgroundColor: colorFor(summary.color_index ?? 0),
          }
        }),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        scales: {
          x: { grid: { display: false }, ticks: { color: AXIS_COLOR, maxRotation: 0, autoSkipPadding: 16 } },
          y: {
            beginAtZero: true,
            suggestedMax: 24,
            title: { display: true, text: "Hours at risk", color: AXIS_COLOR },
            grid: { color: GRID_COLOR },
            ticks: { color: AXIS_COLOR, precision: 0 },
          },
        },
        plugins: {
          legend: { position: "bottom", labels: { usePointStyle: true, color: "#0b0b0b" } },
          tooltip: {
            callbacks: {
              label: (item) =>
                item.raw === null
                  ? `${item.dataset.label}: no readings`
                  : `${item.dataset.label}: ${item.raw} h at risk`,
            },
          },
        },
      },
    })
  }

  #ariaLabel() {
    const parts = this.summariesValue.map((summary) => {
      const worst = summary.days.reduce(
        (max, day) => (day.at_risk_hours > max.at_risk_hours ? day : max),
        { at_risk_hours: 0, date: null },
      )
      if (!worst.date) return `${summary.name}: no day came under the threshold`
      return `${summary.name}: worst day ${worst.date}, ${worst.at_risk_hours} hours at risk`
    })

    return `Hours at risk per day. ${parts.join(". ")}. The totals are also listed as text above.`
  }
}
```

- [ ] **Step 2: Give each summary its colour index**

The bars reuse the sensor's colour so they match the margin line above them. In `app/services/climate/risk_summary.rb`, add the colour to `summarise`:

```ruby
    def initialize(sensors:, range:, threshold: Climate::CONDENSATION_RISK_MARGIN)
      @sensors = Array(sensors)
      @range = range
      @threshold = threshold
      @colors = SeriesColors.new
    end
```

and inside the returned hash, after `name:`:

```ruby
        color_index: @colors.index_for(sensor),
```

Add the matching assertion to `test/services/climate/risk_summary_test.rb`:

```ruby
  test "carries the sensor's own colour index so the bars match its line" do
    sensor = create_climate_sensor(in_crypt: true)

    expected = Climate::SeriesColors.new.index_for(sensor)

    assert_equal expected, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:color_index]
  end
```

- [ ] **Step 3: Render the bars**

In `app/views/admin/climate/dashboard/_condensation_risk.html.erb`, after the margin chart block (still inside the `else` branch):

```erb
    <% if risk.any? { |summary| summary[:days].any? } %>
      <p class="mt-6 mb-2 text-sm text-gray-600">
        Hours at risk per day. A day with no bar had readings and stayed clear; a day with no
        column at all had no readings.
      </p>
      <div data-controller="climate-risk-bars"
           data-climate-risk-bars-summaries-value="<%= risk.to_json %>">
        <div class="relative h-48"><canvas data-climate-risk-bars-target="canvas"></canvas></div>
      </div>
    <% end %>
```

- [ ] **Step 4: Run, lint and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/services/climate/risk_summary_test.rb test/functional/admin/climate
pnpm exec eslint app/javascript/controllers/climate_risk_bars_controller.js
git add app/javascript/controllers/climate_risk_bars_controller.js \
        app/services/climate/risk_summary.rb test/services/climate/risk_summary_test.rb \
        app/views/admin/climate/dashboard/_condensation_risk.html.erb
git commit -m "feat(climate): chart hours at risk per day

$(cat <<'MSG'
A bad week reads as a cluster rather than being buried in a single total. A
day the sensor did not cover is left null rather than zero, because zero would
read as measured and fine.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 10: The ventilation card

**Files:**
- Create: `app/javascript/controllers/climate_ventilation_chart_controller.js`
- Create: `app/views/admin/climate/dashboard/_ventilation.html.erb`
- Modify: `app/views/admin/climate/dashboard/show.html.erb`
- Test: `test/functional/admin/climate/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `@ventilation`, `@range`.
- Produces: Stimulus controller `climate-ventilation-chart` with a `series` (Array) value, exposing `element.climateCharts` and `data-climate-ventilation-chart-ready`.

- [ ] **Step 1: Write the controller**

`app/javascript/controllers/climate_ventilation_chart_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import {
  colorFor, endLabelPlugin, legendAndTooltip, loadChartJs, reducedMotion,
  seriesAriaLabel, timeScaleOptions, withAlpha,
} from "../lib/climate_chart"

// Crypt temperature, crypt dew point and outdoor dew point on one °C axis, so
// the two ventilation questions can be read off a single picture.
//
// The styles are load-bearing: the two crypt lines share the sensor's hue so
// they read as one place, the outdoor line is dashed so it reads apart
// without relying on colour.
const STYLES = {
  solid: { borderDash: [], borderWidth: 2, alpha: 1 },
  muted: { borderDash: [2, 3], borderWidth: 2, alpha: 0.65 },
  dashed: { borderDash: [6, 4], borderWidth: 2, alpha: 1 },
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = { series: Array }

  #charts = []

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateVentilationChartReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateVentilationChartReady
  }

  #build(Chart) {
    const canvas = this.canvasTarget
    const title = "Temperature and dew point (°C)"

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit: "°C",
      entries: this.seriesValue.map((line) => ({
        name: line.label, values: line.points.map((point) => point.value),
      })),
      suffix: "Ventilating dries the crypt when the outside dew point sits below the crypt's own.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: {
        datasets: this.seriesValue.map((line) => {
          const style = STYLES[line.style] ?? STYLES.solid
          const color = withAlpha(colorFor(line.color_index), style.alpha)
          return {
            label: line.label,
            spanGaps: false,
            data: line.points.map((point) => ({ x: point.t, y: point.value })),
            borderColor: color,
            backgroundColor: color,
            borderDash: style.borderDash,
            borderWidth: style.borderWidth,
            pointRadius: 0,
            pointHoverRadius: 5,
            tension: 0.2,
          }
        }),
      },
      plugins: [endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        interaction: { mode: "index", intersect: false },
        layout: { padding: { right: 0 } },
        scales: timeScaleOptions({ title, unit: "°C" }),
        plugins: legendAndTooltip({ unit: "°C" }),
      },
    })
  }
}
```

- [ ] **Step 2: Write the partial**

`app/views/admin/climate/dashboard/_ventilation.html.erb`:

```erb
<%= render CardComponent.new(title: "Ventilation", html_class: "mb-4") do %>
  <% if ventilation.sensor.nil? %>
    <p class="text-gray-600 mb-0">
      No sensors are marked as being in the crypt.
      <%= link_to "Tick one on the sensor list", admin_climate_sensors_path, class: "text-primary underline" %>
      to compare it with the air outside.
    </p>
  <% else %>
    <p class="mb-3 text-gray-600">
      All three lines are °C, which is the point: relative humidity can't be compared between two
      places at different temperatures, but dew point can. <strong>Outside dew point below the
      crypt's own dew point</strong> means the air out there is drier in absolute terms, so opening
      up dries the crypt. <strong>Outside dew point above the crypt's temperature</strong> means
      you'd be pumping in air that condenses on cold stone, however dry the day feels. And the
      walls are colder than the air shown here, so treat the temperature line as optimistic.
    </p>

    <%= form_with url: admin_climate_dashboard_path, method: :get, data: { turbo: false },
                  class: "flex flex-wrap items-end gap-3 mb-4" do |f| %>
      <%= hidden_field_tag :from, @range.from.iso8601 %>
      <%= hidden_field_tag :to, @range.to.iso8601 %>
      <div>
        <%= label_tag :crypt, "Crypt sensor", class: "block text-sm text-gray-600" %>
        <%= select_tag :crypt, options_for_select(ventilation.options, ventilation.selected_key),
                       class: "form-control" %>
      </div>
      <%= f.submit "Show", class: btn_classes(:secondary) %>
    <% end %>

    <% if ventilation.series.any? { |line| line[:points].any? } %>
      <div data-controller="climate-ventilation-chart"
           data-climate-ventilation-chart-series-value="<%= ventilation.series.to_json %>">
        <div class="relative h-64"><canvas data-climate-ventilation-chart-target="canvas"></canvas></div>
      </div>
    <% else %>
      <p class="text-gray-600 mb-0">No readings in this range yet.</p>
    <% end %>

    <% if ventilation.series.none? { |line| line[:key] == "outdoor_dew_point" } %>
      <p class="mt-3 mb-0 text-sm text-amber-800">
        The outside line is missing, so only the crypt is shown. Outside conditions are fetched
        hourly and fill their own gaps on the next successful poll.
      </p>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Render it**

In `app/views/admin/climate/dashboard/show.html.erb`, after the condensation-risk render and before the `History` card:

```erb
<%= render "ventilation", ventilation: @ventilation %>
```

- [ ] **Step 4: Add rendering assertions**

Append to `test/functional/admin/climate/dashboard_controller_test.rb`:

```ruby
      test "offers every crypt sensor in the ventilation picker" do
        north = create_climate_sensor(display_name: "Crypt north", in_crypt: true)
        create_climate_reading(sensor: north, recorded_at: 2.hours.ago)

        get :show

        assert_match(/Coldest crypt sensor/, response.body)
        assert_match(/Crypt north/, response.body)
      end

      test "says the outside line is missing when the feed has no readings" do
        sensor = create_climate_sensor(in_crypt: true)
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show

        assert_match(/outside line is missing/, response.body)
      end
```

- [ ] **Step 5: Run, lint and commit**

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test test/functional/admin/climate
pnpm exec eslint app/javascript/controllers/climate_ventilation_chart_controller.js
bundle exec herb lint app/views/admin/climate/dashboard
git add app/javascript/controllers/climate_ventilation_chart_controller.js \
        app/views/admin/climate/dashboard test/functional/admin/climate/dashboard_controller_test.rb
git commit -m "feat(climate): chart when it is worth opening the crypt up

$(cat <<'MSG'
Three lines on one °C axis, which is the point: relative humidity cannot be
compared between two places at different temperatures, but dew point can. The
two crypt lines share the sensor's hue so they read as one place; the outdoor
line is dashed so it reads apart without relying on colour.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 11: System tests for the new charts

**Files:**
- Create: `test/system/admin/climate/risk_charts_js_test.rb`

**Interfaces:**
- Consumes: every controller from Tasks 8–10 and their `element.climateCharts` handles.

- [ ] **Step 1: Write the system test**

`test/system/admin/climate/risk_charts_js_test.rb`:

```ruby
require "application_system_test_case"

module Admin
  module Climate
    # Browser tests for the condensation-risk and ventilation charts. The
    # functional tests prove the ERB renders and the payload is right; only a
    # real browser proves Chart.js draws, and that it plots the values it was
    # handed rather than some neighbouring column.
    class RiskChartsJsTest < ApplicationSystemTestCase
      include ClimateTestHelpers

      setup do
        role = ::Role.create!(name: "Climate Viewer")
        role.permissions << ::Admin::Permission.create(action: "read", subject_class: "climate")
        role.permissions << ::Admin::Permission.create(action: "access", subject_class: "backend")
        users(:member).add_role("Climate Viewer")
        login_as users(:member)

        @crypt = create_climate_sensor(display_name: "Crypt north", location: "North wall", in_crypt: true)
        @outdoor = outdoor_climate_sensor
        seed_readings
      end

      # Deliberately distinct values per sensor and per measure, so a chart
      # plotting the wrong series or the wrong column cannot pass. The crypt
      # margin is a flat 2.0 °C, under the 3.0 threshold.
      def seed_readings
        base = 6.hours.ago.change(min: 0)
        12.times do |index|
          create_climate_reading(sensor: @crypt, recorded_at: base + (index * 30).minutes,
                                 temperature_c: 11.0, relative_humidity: 85.0, dew_point_c: 9.0)
          create_climate_reading(sensor: @outdoor, recorded_at: base + (index * 30).minutes,
                                 temperature_c: 17.0, relative_humidity: 65.0, dew_point_c: 6.0)
        end
      end

      def plotted(selector, label)
        evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector(#{selector.to_json})
            const set = root.climateCharts[0].data.datasets.find(d => d.label === #{label.to_json})
            return set ? set.data.map(p => p.y) : null
          })()
        JS
      end

      test "plots the margin, not the temperature" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-margin-chart-ready='1']"

        values = plotted("[data-controller='climate-margin-chart']", "Crypt north").compact

        assert_predicate values, :any?
        values.each { |value| assert_in_delta 2.0, value, 0.001 }
      end

      test "states the hours at risk as text as well" do
        visit admin_climate_dashboard_path

        assert_text(/hours? with readings/)
      end

      test "plots all three ventilation lines on one axis" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-ventilation-chart-ready='1']"

        selector = "[data-controller='climate-ventilation-chart']"

        assert_in_delta 11.0, plotted(selector, "Crypt north temperature").compact.first, 0.001
        assert_in_delta 9.0, plotted(selector, "Crypt north dew point").compact.first, 0.001
        assert_in_delta 6.0, plotted(selector, "Outside dew point").compact.first, 0.001
      end

      test "the crypt selector is carried in the url" do
        visit admin_climate_dashboard_path(crypt: @crypt.id.to_s)
        assert_selector "[data-climate-ventilation-chart-ready='1']"

        assert_equal @crypt.id.to_s, find("#crypt").value
      end

      test "tears the charts down on navigation" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-margin-chart-ready='1']"

        click_on "Sensors"

        assert_no_selector "[data-climate-margin-chart-ready]"
      end
    end
  end
end
```

- [ ] **Step 2: Run the system tests**

Stop `bin/dev` first — a running dev server collides with the system-test port.

```bash
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test:system TEST=test/system/admin/climate/risk_charts_js_test.rb
```
Expected: PASS. If `click_on "Sensors"` fails because the link is only rendered for a manager, grant `grant_climate_manage_permission(users(:member))` in setup instead.

- [ ] **Step 3: Commit**

```bash
git add test/system/admin/climate/risk_charts_js_test.rb
git commit -m "test(climate): drive the risk and ventilation charts in a browser

$(cat <<'MSG'
Seeds a flat 2 °C margin and distinct values per measure, so a chart plotting
the wrong column cannot pass.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

---

### Task 12: Copy, docs and full verification

**Files:**
- Modify: `app/views/admin/climate/dashboard/show.html.erb` (the intro paragraph and the "How this works" list)
- Modify: `CLAUDE.md`
- Modify: `docs/climate/csv-import.md` — line 3 says the monitor "charts temperature, relative humidity and dew point", which is now incomplete; line 93 already explains the dew-point margin and should point at the risk chart.

**Interfaces:** none — this task ships no new behaviour.

- [ ] **Step 1: Update the intro paragraph**

In `app/views/admin/climate/dashboard/show.html.erb`, replace the opening `<p>` with:

```erb
<p class="mb-3 text-gray-600">
  How close the crypt is to condensing, and whether opening it up would help. Condensation forms
  on any surface at or below the dew point of the air touching it, so the walls need to sit a few
  degrees above the crypt's dew point to keep mould off them.
  <strong>Under <%= number_with_precision(Climate::CONDENSATION_RISK_MARGIN, precision: 0) %> °C of margin is worth acting on</strong>,
  which is roughly 80% humidity at the surface and where mould starts to grow.
</p>
```

- [ ] **Step 2: Extend "How this works"**

In the same file's `CollapsibleSectionComponent` block, replace the "When to open up" bullet with one that points at the new chart, and add two more:

```erb
    <li>
      <strong>When to open up.</strong> That's what the Ventilation chart is for. Compare the
      outside dew point with the crypt — below the crypt's own dew point and ventilating dries the
      place out; above the crypt's temperature and you're pumping in air that will condense on cold
      stone, however dry it feels outside. A warm muggy day is the worst time to air out a
      basement, and a cold crisp one is the best. Relative humidity can't be compared between two
      places at different temperatures, but dew point can.
    </li>
    <li>
      <strong>The risk chart plots the worst point in each bucket, not the average.</strong> Past a
      couple of days the readings are grouped into wider buckets, and a daily average margin can
      sit at a comfortable 5 °C while every night touched 1. Condensation is a worst-case event, so
      that chart shows the worst case.
    </li>
    <li>
      <strong>Hours at risk are counted against hours that have readings</strong>, never against
      hours in the range. The sensors are synced by hand and routinely miss days, so a range
      denominator would report a damp week as a quiet month.
    </li>
    <li>
      <strong>Which sensors count as "the crypt" is a checkbox</strong> on each sensor. Only ticked
      sensors appear in the risk and ventilation charts; the history charts below show everything.
    </li>
```

- [ ] **Step 3: Document it in CLAUDE.md**

In the "Crypt climate monitor" section, after the outdoor-data bullets, add:

```markdown
- **Which sensors are "the crypt" is stored, not inferred** (`Climate::Sensor#in_crypt`). `placement`
  separates indoor from outdoor, but a dressing-room sensor is indoor too and would poison a
  crypt-only worst case. Only ticked sensors feed the risk and ventilation charts; the raw history
  charts still show every active sensor.
- **The margin chart aggregates with `MIN(temperature_c - dew_point_c)`** — per row, then the worst
  of them. NOT `MIN(temperature_c) - MAX(dew_point_c)`, which takes its two figures from different
  instants and invents a crypt that never existed, and not `AVG`, because a daily mean margin can
  sit at 5 °C while every night touched 1. `Climate::MarginSeries` has a test that fails under
  either wrong form.
- **`Climate::RiskSummary` counts against hours that HAVE readings**, never hours in the range: the
  sensors are hand-synced and routinely miss days, so "41 of 720 hours" reads as 6% of a month when
  it means 8% of the six days covered. A coverage gap also **breaks** a continuous spell, the same
  principle as not drawing a line across missing data.
- **`Climate::VentilationSeries`'s worst case is the single coldest crypt sensor**, resolved once
  from the lowest mean temperature over the range — not a composite of the lowest temperature and
  highest dew point across sensors. A chart whose two lines came from different sensors cannot be
  read for the gap between them, and that gap is the first thing anyone reads. It is a projection
  over `SeriesQuery`, not new SQL, so it aggregates with `AVG` deliberately: it is read for the
  present, and `MarginSeries` owns the historical worst case.
- **Bucketing and sensor colours live in `Climate::Buckets` and `Climate::SeriesColors`**, shared by
  all four chart payloads. A margin line bucketed differently from the temperature line above it
  would be unreadable next to it, and a sensor must be the same colour on every chart.
- **Shared Chart.js machinery is in `app/javascript/lib/climate_chart.js`.** Four chart controllers
  and `jscpd` gating at threshold 0 means the palette, the lazy import and the end-label plugin
  cannot be copied per controller.
```

- [ ] **Step 4: Run every check**

```bash
docker start /mysql8
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test
env -u REIMBURSEMENTS_AZURE_CLIENT_ID -u REIMBURSEMENTS_AZURE_CLIENT_SECRET -u REIMBURSEMENTS_AZURE_TENANT_ID \
  bin/rails test:system
hk run check
```
Expected: all green. Ingest the full output; do not tail it.

Known pre-existing failure: `test/system/konami_code_test.rb` errors with `ActiveStorage::FileNotFoundError` on `main` too. Anything else is yours.

- [ ] **Step 5: Look at the page**

With `bin/dev` running, visit `/admin/climate` and confirm by eye:
- the margin line sits above a shaded band and dips into it where expected
- the at-risk sentence agrees with the chart
- the per-day bars line up under it
- the ventilation chart's three lines are distinguishable
- picking a sensor in the dropdown changes the chart and survives changing the dates
- the empty states render when no sensor is ticked

- [ ] **Step 6: Commit and merge**

```bash
git add app/views/admin/climate/dashboard/show.html.erb CLAUDE.md docs/climate/csv-import.md
git commit -m "docs(climate): explain the risk and ventilation charts

$(cat <<'MSG'
Records the aggregation rules in CLAUDE.md, since every one of them is
something a later change could plausibly "simplify" into being wrong.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LHWjonHQQWzUeviEcihpaj
MSG
)"
```

Then use the `superpowers:finishing-a-development-branch` skill to merge `climate-crypt-graphs` into `main` and remove the worktree.

---

## Self-review notes

**Spec coverage.** Every spec section maps to a task: data model → 1; `Buckets`/`SeriesColors` → 2; `MarginSeries` and the threshold move → 3; `RiskSummary` → 4; `VentilationSeries` → 5; controller, URL state and JSON → 6; the JS library and min–max band → 7; page sections 2 and 3 → 8, 9, 10; empty states → 8 and 10; testing → spread across all tasks plus 11; copy and docs → 12.

**Deliberately deferred.** The spec's "Out of scope" list (alerting, wall temperature, absolute humidity) has no task, by design.
