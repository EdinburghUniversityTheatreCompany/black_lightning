# Crypt climate: condensation-risk and ventilation charts

## The problem

The dashboard shows three charts — temperature, relative humidity, dew point — one line per
sensor. Neither of the two questions the feature exists to answer can be read off them.

**"How close did the crypt get to condensing?"** The margin between air temperature and dew
point is the number the whole monitor is for. It exists only as an instantaneous figure on a
`Now` tile. Nobody can see whether last Tuesday night dipped under 3 °C.

**"Should I open the doors?"** The `How this works` copy already tells the reader to compare the
outside dew point against the crypt's temperature. They cannot: those two lines live on
different charts with different y-axes.

There is also a way the existing charts mislead. `SeriesQuery` aggregates with `AVG`, and past
two days the buckets widen to hourly, six-hourly, then daily. A year of daily *mean* margin can
sit comfortably at 5 °C while every night dipped to 1 °C. Condensation is a worst-case event, so
an averaged view of it is the wrong view.

## Decisions

These are settled. They cost real deliberation and should not be re-litigated during
implementation.

**Which sensors are "the crypt" is stored, not inferred.** A new `in_crypt` checkbox. `placement`
already distinguishes indoor from outdoor, but not every indoor sensor is in the crypt — a
dressing-room or upstairs sensor would silently poison a crypt-only average.

**"Worst case" means the coldest sensor, not a synthetic composite.** An earlier draft built a
worst-case crypt from the lowest temperature and the highest dew point across all ticked sensors.
Rejected: those two lines can come from different sensors, and the gap between them is the first
thing anyone reads. Instead the worst case picks the single crypt sensor with the lowest mean
temperature over the range and draws *its* two lines. Still the coldest spot in the crypt, which
is where condensation happens, and every line is a real sensor.

**The margin chart plots the minimum, never the mean.** And it must be `MIN(temperature_c -
dew_point_c)`, computed per row then minimised — **not** `MIN(temperature_c) - MAX(dew_point_c)`,
which takes the two figures from different instants and invents a worse crypt than ever existed.

**Hours at risk are counted against hours that have readings**, not against hours in the range.
"41 of 720 hours" is a lie when the sensor only covered six days of a month. The denominator is
hours with any reading, and the figure is rendered as "41 of the 512 hours with readings".

**A coverage gap breaks a spell.** The longest continuous at-risk spell cannot run through hours
with no data — the same principle as `SeriesQuery#with_gaps` refusing to draw a line across an
outage. Claiming 30 unbroken damp hours across a 20-hour hole is a measurement that never
happened.

**The ventilation chart aggregates with `AVG`, deliberately.** It answers "should I open up
*now*", which is read over the last day or two, where buckets are raw anyway. The historical
worst case is the margin chart's job, and doing both on one chart would mean two lines pessimised
for different questions with a meaningless gap between them.

**All of this measures air, not stone.** The walls are underground and colder than the air, so
both new charts flatter the situation exactly as the existing copy warns. The caveat is repeated
on the new sections rather than assumed to have been read further up the page.

## Data model

```ruby
add_column :climate_sensors, :in_crypt, :boolean, default: false, null: false
```

The same migration backfills existing indoor Govee sensors:

```ruby
reversible do |direction|
  direction.up do
    execute("UPDATE climate_sensors SET in_crypt = TRUE WHERE placement = 'indoor' AND source = 'govee'")
  end
end
```

A data migration is safe here, unlike `Sensor.outdoor_source!`. That had to be ensured at runtime
because test and CI databases are schema-*loaded*, so a migration would leave every environment
except production without the row. A backfill only has to touch rows that already exist, and
test/CI have none. Rollback drops the column, so no `down` body is needed.

No index: the table holds a handful of rows.

`Climate::Sensor` gains `scope :in_crypt` and a validation rejecting `in_crypt` on an outdoor
sensor, so the Open-Meteo row cannot be marked as sitting in the crypt.
`Admin::Climate::SensorsController#sensor_params` permits `:in_crypt`; the form gets a checkbox
hinted "Include this sensor in the condensation-risk and ventilation charts."

`ClimateHelper::CONDENSATION_RISK_MARGIN` moves to the `Climate` module namespace so services can
read it without reaching into a view helper. The helper keeps working through the moved constant.

## Services

Two extractions from `SeriesQuery`, so four callers share one rule rather than four copies:

- **`Climate::Buckets`** — the resolution table, the `TIME_TO_SEC` bucket expressions, and gap
  insertion. `#seconds`, `#expression`, `#with_gaps(points, keys:)`. The `UNIX_TIMESTAMP` warning
  in the current comments moves with it: the mysql2 adapter does not pin the session `time_zone`,
  so that function reads the stored value in the server's zone and shifts every bucket boundary.
- **`Climate::SeriesColors`** — `#index_for(sensor)`, ranking by id across *all* sensors so a
  sensor keeps its colour when another is deactivated. Now shared, so a sensor is the same colour
  on every chart on the page, which is what makes them readable together.

Three new services:

- **`Climate::MarginSeries`** — crypt sensors + range → `[{ id:, name:, color_index:, points:
  [{ t:, margin: }] }]`, grouped by sensor and bucket on `MIN(temperature_c - dew_point_c)`.
- **`Climate::RiskSummary`** — crypt sensors + range → per sensor `{ hours_with_readings:,
  hours_at_risk:, longest_spell_hours:, longest_spell_ended_at:, days: [{ date:, at_risk_hours:,
  hours_with_readings: }] }`. One query: hourly buckets of `MIN(temperature_c - dew_point_c)`,
  then counted in Ruby. Hours are the unit throughout, so the three figures and the bars all
  derive from the same rows.
- **`Climate::VentilationSeries`** — a thin projection over `SeriesQuery`, not new SQL. It
  resolves the selection (`"worst"` → lowest mean temperature among crypt sensors, otherwise a
  sensor id), calls `SeriesQuery` for that sensor plus the outdoor one, and re-labels the result
  as three datasets: crypt temperature, crypt dew point, outdoor dew point. Also returns the
  dropdown options and the resolved sensor.

`SeriesQuery` keeps its public API and additionally plucks `MIN`/`MAX` per measure.

## Aggregation

| Series | Aggregate | Why |
|---|---|---|
| Margin chart | `MIN(temperature_c - dew_point_c)` | Per row then minimised. The other order invents a crypt that never existed. |
| Existing three charts | `AVG`, plus a low-alpha `MIN`–`MAX` band | Band drawn only once buckets exceed 10 minutes; below that min equals max and it is a zero-width artefact. |
| Ventilation chart | `AVG` on all three lines | Read for the present, where buckets are raw. |
| Hours at risk | hourly `MIN(margin)`, count hours under the threshold | Denominator is hours with readings. |
| Longest spell | consecutive at-risk hours | A coverage gap breaks the run. |

## Client

`climate_charts_controller.js` is already 227 lines and would roughly triple. Instead, the shared
machinery moves to `app/javascript/lib/climate_chart.js` — the palette, the lazy Chart.js import,
the end-of-line label plugin, the base options, the aria-label builder — and four thin
controllers use it:

- `climate_charts_controller` (existing three, plus the min–max band)
- `climate_margin_chart_controller` (margin line, plus a risk-band plugin filling below the
  threshold, in the same inline-plugin style as the existing end-label plugin)
- `climate_risk_bars_controller` (per-day bars; registers `BarController`, `BarElement`,
  `CategoryScale`)
- `climate_ventilation_chart_controller`

The extraction is not optional: `jscpd` is a gating check at threshold 0, so four controllers each
carrying their own copy of the palette and import would fail the build.

Each controller keeps the existing conventions: `spanGaps: false` so server-inserted nulls break
the line, an `element.climateCharts` handle and a `data-*-ready` count so system tests can assert
the exact plotted values, `role="img"` with a generated aria-label, and `destroy()` on disconnect
so Turbo navigation does not leak canvases.

## Page

Answer first, evidence second:

1. **Now** — tiles, unchanged.
2. **Condensation risk** — the three at-risk figures per crypt sensor as real HTML, then the
   margin chart with the sub-threshold band shaded, then the per-day bars.
3. **Ventilation** — the sensor selector, then the three-line °C chart.
4. **History** — the existing three charts, now banded.
5. **How this works** — extended to cover the new charts and repeat the walls-are-colder caveat.

The at-risk figures are HTML rather than canvas for the same reason the `Now` tiles are: the
question that matters must not depend on a chart rendering, and screen readers get it directly.

## URL state

`?crypt=worst` or `?crypt=<sensor_id>`, alongside the existing `from`/`to`. The date form and the
range presets carry it through, so changing the range does not reset the selection. An unknown or
non-crypt id falls back to `worst` **and flashes that it did**, matching `DateRange`'s habit of
clamping loudly rather than silently rendering something other than what was asked for.

`format.json` gains `margin:`, `risk:` and `ventilation:` keys, so the new charts can be checked
without reading pixels off a canvas.

## Empty states

- **No sensor ticked as in the crypt** — sections 2 and 3 render "No sensors are marked as being
  in the crypt" with a link to the sensor list, not empty canvases. Nothing is guessed; falling
  back to "all indoor sensors" would make the checkbox do nothing until first ticked.
- **Ticked, but no readings in range** — the existing "no readings in this range yet" copy.
- **No outdoor readings in range** — the ventilation chart still draws the two crypt lines and
  says the outdoor line is missing, rather than rendering nothing.

## Testing

Every row of the aggregation table gets a test that fails under the wrong aggregate — that table
is where the bugs live.

- `Buckets` — resolution selection per span, gap insertion, and that bucket boundaries do not
  shift with the server time zone.
- `SeriesColors` — a sensor keeps its colour when a lower-id sensor is deactivated.
- `MarginSeries` — seed a bucket whose minimum margin and whose (min temp − max dew) differ, and
  assert the former. This is the test that fails if someone "simplifies" the SQL.
- `RiskSummary` — the denominator counts hours with readings, not hours in the range; a spell
  is broken by a coverage gap; per-day bars sum to the headline figure.
- `VentilationSeries` — worst case picks the coldest sensor; an unknown id falls back and sets a
  notice; a non-crypt id is not selectable.
- `Sensor` — `in_crypt` is rejected on an outdoor sensor.
- Migration — rollback actually run, not assumed.
- Controller — the JSON payload shape, and the empty states.
- System — plotted values read off `element.climateCharts`, per the existing pattern. Note that
  `bin/rails test` does not run these; `bin/rails test:system` does.

## Out of scope

- **Alerting** when the margin sits low for N hours. Real, and probably next, but not a graph.
- **Wall temperature.** The honest fix for the air-not-stone caveat needs hardware.
- **Absolute humidity in g/m³.** Dew point already answers "is there more water in here than out
  there", and a fourth unit on the page is noise.
