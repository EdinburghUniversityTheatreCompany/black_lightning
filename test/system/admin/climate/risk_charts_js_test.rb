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
        # "manage" rather than "read": CanCan's :manage matches :read too (see
        # ClimateTestHelpers#grant_climate_manage_permission), and the "tears
        # the charts down" test below needs the "Sensors" link, which the
        # dashboard only renders for can?(:manage, :climate).
        role = ::Role.create!(name: "Climate Manager")
        role.permissions << ::Admin::Permission.create(action: "manage", subject_class: "climate")
        role.permissions << ::Admin::Permission.create(action: "access", subject_class: "backend")
        users(:member).add_role("Climate Manager")
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

      # The shaded risk band is drawn by a canvas plugin, not a dataset, so it
      # cannot be read off plotted points the way the margin line above is.
      # Chart.js keeps the plugins a chart was actually built with on
      # chart.config.plugins (see node_modules/chart.js/dist/chart.js's Config
      # class) — asserting the band plugin is really wired into the built
      # chart, with the threshold value the server sent, is the closest a
      # browser test gets to "the shaded band renders" without reading pixels.
      test "the margin chart's risk band is wired in with the server's threshold" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-margin-chart-ready='1']"

        plugin_ids = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-margin-chart']")
            .climateCharts[0].config.plugins.map(p => p.id)
        JS
        assert_includes plugin_ids, "climateRiskBand"

        threshold = find("[data-controller='climate-margin-chart']")["data-climate-margin-chart-threshold-value"]
        assert_equal ::Climate::CONDENSATION_RISK_MARGIN.to_s, threshold
      end

      test "states the hours at risk as text as well" do
        visit admin_climate_dashboard_path

        assert_text(/hours? with readings/)
      end

      # Every hour in the seeded 6-hour span sits at a flat 2.0 °C margin,
      # under the 3.0 °C threshold, so every hourly bucket the sensor covered
      # counts as at risk. That is the same total the risk sentence above
      # states as text — this proves the JS bars reflect the same numbers, not
      # merely that a canvas exists.
      test "the per-day bars draw the hours at risk" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-risk-bars-ready='1']"

        totals = evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector("[data-controller='climate-risk-bars']")
            return root.climateCharts[0].data.datasets.map(
              (ds) => ds.data.filter((v) => v !== null).reduce((sum, v) => sum + v, 0)
            )
          })()
        JS

        assert_equal [ 6 ], totals
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

      # --- the min-max band: present once buckets widen, absent at raw ------
      #
      # Climate::SeriesQuery#aggregated? / Climate::Buckets#aggregated? is
      # false while a bucket holds at most one reading (a chart bucketed at
      # raw ten-minute resolution), and true once bucketing starts averaging
      # more than one reading per point. A band drawn at raw resolution would
      # be a zero-width artefact; earlier tasks only proved this server-side
      # (see Climate::SeriesQuery), because nothing before this task read
      # what Chart.js actually received.
      test "the min-max band appears once buckets widen, and is absent at raw resolution" do
        ::Climate::Reading.delete_all
        day = Date.parse("2026-08-05")

        [ 0, 30, 90, 120 ].each do |minutes|
          create_climate_reading(sensor: @crypt, recorded_at: day.beginning_of_day + minutes.minutes,
                                 temperature_c: 11.0, relative_humidity: 85.0, dew_point_c: 9.0)
        end

        visit admin_climate_dashboard_path(from: day.iso8601, to: day.iso8601)
        assert_selector "[data-climate-charts-ready='3']"

        raw_band = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']")
            .climateCharts[0].data.datasets.some((d) => d.band)
        JS
        assert_not raw_band, "expected no min-max band at raw (ten-minute) resolution"

        visit admin_climate_dashboard_path(from: (day - 6).iso8601, to: day.iso8601)
        assert_selector "[data-climate-charts-ready='3']"

        wide_band = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']")
            .climateCharts[0].data.datasets.some((d) => d.band)
        JS
        assert wide_band, "expected a min-max band once buckets are wider than raw resolution"
      end

      # --- regression: the outdoor line must draw on the 24-hour view -------
      #
      # Production bug: on the 24-hour view the outdoor line never drew, on
      # any chart, while the crypt line drew fine. Cause: Climate::Buckets
      # #with_gaps derived its gap threshold from the CHART's bucket width
      # (600s at 24h resolution) rather than the SERIES' own cadence.
      # Open-Meteo reports hourly, so every consecutive pair of real outdoor
      # points was 3600s apart — over the 1800s threshold (600 * GAP_BUCKETS)
      # — and an explicit null got inserted after every single real point.
      # With spanGaps: false and pointRadius: 0 that leaves no two adjacent
      # real values anywhere in the dataset, so nothing was drawable: not a
      # missing dataset (that would already fail a "dataset exists" check),
      # not a wrong point count (still 2x the real count, nulls included) —
      # only an adjacency check on the actual plotted values catches it.
      #
      # Fixed: the threshold is now derived from the series' own observed
      # cadence (Buckets#gap_threshold), clamped so it can never be smaller
      # than the chart's own bucket width. Needs >= 3 outdoor points so the
      # cadence is measured from two real deltas rather than falling back to
      # the two-point/single-delta case, which still uses the bucket width
      # (see Buckets#gap_threshold and BucketsTest's two-point fallback test).
      test "the outdoor line draws a run of adjacent points on the 24-hour view" do
        ::Climate::Reading.delete_all
        day = Date.parse("2026-08-05")
        start = day.beginning_of_day

        # The crypt's real cadence: every ten minutes, for six hours.
        36.times do |index|
          create_climate_reading(sensor: @crypt, recorded_at: start + (index * 10).minutes,
                                 temperature_c: 11.0, relative_humidity: 85.0, dew_point_c: 9.0)
        end

        # Open-Meteo's real cadence: hourly, across the whole day. Five points
        # so gap_threshold has two real deltas to measure the cadence from.
        5.times do |hour|
          create_climate_reading(sensor: @outdoor, recorded_at: start + hour.hours,
                                 temperature_c: 17.0, relative_humidity: 65.0, dew_point_c: 6.0)
        end

        visit admin_climate_dashboard_path(from: day.iso8601, to: day.iso8601)
        assert_selector "[data-climate-charts-ready='3']"

        outdoor_y = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']")
            .climateCharts[0].data.datasets
            .find((d) => d.label === #{@outdoor.display_name.to_json}).data.map((p) => p.y)
        JS

        adjacent_real_pair = outdoor_y.each_cons(2).any? { |a, b| !a.nil? && !b.nil? }

        assert adjacent_real_pair,
               "expected two adjacent plotted outdoor points with no null between them, " \
               "so Chart.js has a line segment to draw; got #{outdoor_y.inspect}"
      end
    end
  end
end
