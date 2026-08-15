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
      # plotting the wrong series or the wrong column cannot pass.
      #
      # The crypt margin is 2.0 °C for the first four hours and 4.0 °C for the
      # last two, so the at-risk count is a strict SUBSET of the hours covered.
      # A flat at-risk margin would leave the two indistinguishable, and a bars
      # chart reading hours_with_readings instead of at_risk_hours would pass.
      def seed_readings
        base = 6.hours.ago.change(min: 0)
        12.times do |index|
          clear = index >= 8 # the last two hourly buckets sit above the threshold
          create_climate_reading(sensor: @crypt, recorded_at: base + (index * 30).minutes,
                                 temperature_c: clear ? 13.0 : 11.0, relative_humidity: 85.0,
                                 dew_point_c: 9.0)
          create_climate_reading(sensor: @outdoor, recorded_at: base + (index * 30).minutes,
                                 temperature_c: 17.0, relative_humidity: 65.0, dew_point_c: 6.0)
        end
      end

      def plotted(selector, label)
        evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector(#{selector.to_json})
            // A band dataset shares its line's label — exclude it even though
            // none of this file's charts build one today (see charts_js_test.rb).
            const set = root.climateCharts[0].data.datasets.find(d => d.label === #{label.to_json} && !d.band)
            return set ? set.data.map(p => p.y) : null
          })()
        JS
      end

      test "plots the margin, not the temperature" do
        visit admin_climate_dashboard_path
        assert_selector "[data-climate-margin-chart-ready='1']"

        values = plotted("[data-controller='climate-margin-chart']", "Crypt north").compact

        assert_predicate values, :any?
        # 2.0 and 4.0 are the seeded margins; 11.0 and 13.0 are the temperatures
        # they were derived from, so a chart plotting the wrong column misses by
        # a wide margin rather than by a rounding error.
        assert_in_delta 2.0, values.min, 0.001
        assert_in_delta 4.0, values.max, 0.001
      end

      # The shaded risk band is a canvas plugin, not a dataset, so it can't be
      # read off plotted points the way the margin line above is. Asserting the
      # plugin is wired into chart.config.plugins with the server's threshold
      # is the closest a browser test gets to "the band renders" without
      # reading pixels.
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

      # Four of the six seeded hours sit under the 3.0 °C threshold and two sit
      # above it, so the bars must total FOUR. Six would mean the chart is
      # plotting hours_with_readings, which is the payload key next to the one
      # it wants and would be invisible against a uniformly at-risk seed.
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

        assert_equal [ 4 ], totals
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
      # A band drawn at raw (one-reading-per-bucket) resolution would be a
      # zero-width artefact. Buckets#aggregated? guards this server-side, but
      # nothing before this test read what Chart.js actually received.
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
      # Production bug: the outdoor line never drew on the 24-hour view, on
      # any chart, while the crypt line drew fine. Cause: Buckets#with_gaps
      # derived its gap threshold from the CHART's bucket width (600s) rather
      # than the SERIES' own cadence, so every real 3600s-apart Open-Meteo
      # pair exceeded the 1800s threshold and got a null inserted between
      # them — no two adjacent real values survived anywhere. Neither a
      # "dataset exists" check nor a point-count check would have caught it
      # (still 2x the real count, nulls included); only an adjacency check on
      # the actual plotted values does. Fixed by deriving the threshold from
      # the series' own cadence (Buckets#gap_threshold), clamped to never go
      # below the chart's bucket width. >= 3 outdoor points here so the
      # cadence comes from two real deltas, not the two-point fallback.
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

        # Every seeded hour survives, with no null anywhere: asserting the whole
        # series rather than "some adjacent pair exists" also rejects a partial
        # regression that breaks only part of the line.
        assert_equal [ 17.0 ] * 5, outdoor_y,
                     "expected five adjacent plotted outdoor points with no null between them, " \
                     "so Chart.js has a line segment to draw; got #{outdoor_y.inspect}"
      end
    end
  end
end
