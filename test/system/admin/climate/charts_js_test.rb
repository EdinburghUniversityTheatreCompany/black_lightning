require_relative "charts_system_test_case"

module Admin
  module Climate
    # Browser tests for the history charts: only a real browser proves Chart.js
    # draws and plots the values it was given. There is no window.Chart, so the
    # controller's instances are read off the element.
    class ChartsJsTest < ChartsSystemTestCase
      setup do
        @sensor = create_climate_sensor(display_name: "Crypt north")
        @outdoor = outdoor_climate_sensor
        seed_readings
      end

      # Distinct values per sensor and measure, so a chart plotting the wrong
      # series or column cannot pass.
      def seed_readings
        base = 6.hours.ago.change(min: 0)
        12.times do |index|
          create_climate_reading(sensor: @sensor, recorded_at: base + (index * 30).minutes,
                                 temperature_c: 11.0 + (index * 0.1), relative_humidity: 85.0,
                                 dew_point_c: 9.0)
          create_climate_reading(sensor: @outdoor, recorded_at: base + (index * 30).minutes,
                                 temperature_c: 17.0 + (index * 0.1), relative_humidity: 65.0,
                                 dew_point_c: 10.0)
        end
      end

      def wait_for_charts
        assert_selector "[data-climate-charts-ready='3']"
      end

      # chart_index: 0 temperature, 1 humidity, 2 dew point. Band datasets share
      # their line's label, so they are excluded to return the plotted line.
      def plotted(chart_index, label)
        evaluate_script(<<~JS)
          (() => {
            const root = document.querySelector("[data-controller='climate-charts']")
            const chart = root.climateCharts[#{chart_index}]
            const set = chart.data.datasets.find(d => d.label === #{label.to_json} && !d.band)
            return set ? set.data.map(p => p.y) : null
          })()
        JS
      end

      test "each chart plots its own measure for each sensor" do
        visit admin_climate_dashboard_path
        wait_for_charts

        # Hourly buckets average the two readings in each hour.
        assert_equal [ 11.05, 11.25, 11.45, 11.65, 11.85, 12.05 ], plotted(0, "Crypt north")
        assert_equal [ 17.05, 17.25, 17.45, 17.65, 17.85, 18.05 ], plotted(0, @outdoor.display_name)
        assert_equal [ 85.0 ] * 6, plotted(1, "Crypt north")
        assert_equal [ 65.0 ] * 6, plotted(1, @outdoor.display_name)
        assert_equal [ 9.0 ] * 6, plotted(2, "Crypt north")
        assert_equal [ 10.0 ] * 6, plotted(2, @outdoor.display_name)
      end

      test "the outdoor line is dashed so it reads apart from the sensors" do
        visit admin_climate_dashboard_path
        wait_for_charts

        # Bands carry no borderDash (shading, not a stroke), so exclude them.
        dashes = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']").climateCharts[0]
            .data.datasets.filter(d => !d.band).map(d => ({ label: d.label, dash: d.borderDash.length }))
        JS

        assert_operator dashes.find { |d| d["label"] == @outdoor.display_name }["dash"], :>, 0
        assert_equal 0, dashes.find { |d| d["label"] == "Crypt north" }["dash"]
      end

      test "lines break across a gap rather than interpolating through it" do
        # spanGaps false plus the server's nulls stops an outage being drawn as
        # an invented straight line. Bands carry it too, so assert every dataset.
        visit admin_climate_dashboard_path
        wait_for_charts

        span_gaps = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']").climateCharts[0]
            .data.datasets.map(d => d.spanGaps)
        JS

        assert_operator span_gaps.length, :>, 0
        assert_equal [ false ] * span_gaps.length, span_gaps
      end

      test "each canvas has an accessible label naming its latest values" do
        visit admin_climate_dashboard_path
        wait_for_charts

        label = find("canvas[data-climate-charts-target='temperature']")["aria-label"]

        assert_match(/Temperature/, label)
        assert_match(/Crypt north/, label)
      end

      test "the date range becomes readable url state" do
        visit admin_climate_dashboard_path
        click_on "7 days"

        assert_current_path(/from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}/)
        wait_for_charts
      end

      # The default 7-day range is already banded (Buckets::RESOLUTIONS), so
      # every test here exercises band datasets.
      test "hiding a sensor via the legend also hides its shaded band" do
        visit admin_climate_dashboard_path
        wait_for_charts

        hidden_before, hidden_after = evaluate_script(<<~JS)
          (() => {
            const chart = document.querySelector("[data-controller='climate-charts']").climateCharts[0]
            const label = "Crypt north"
            const item = chart.legend.legendItems.find(i => i.text === label)
            const indexesForLabel = () => chart.data.datasets
              .map((dataset, index) => (dataset.label === label ? index : null))
              .filter(index => index !== null)

            const before = indexesForLabel().map(index => Boolean(chart.getDatasetMeta(index).hidden))
            chart.options.plugins.legend.onClick({}, item, chart.legend)
            const after = indexesForLabel().map(index => Boolean(chart.getDatasetMeta(index).hidden))
            return [before, after]
          })()
        JS

        # Three datasets share the label while banded: the line plus its max/min band.
        assert_equal [ false, false, false ], hidden_before
        assert_equal [ true, true, true ], hidden_after
      end

      # A band at raw resolution would be a zero-width artefact.
      test "no min-max band at raw resolution" do
        ::Climate::Reading.delete_all
        day = Date.parse("2026-08-05")

        [ 0, 30, 90, 120 ].each do |minutes|
          create_climate_reading(sensor: @sensor, recorded_at: day.beginning_of_day + minutes.minutes,
                                 temperature_c: 11.0, relative_humidity: 85.0, dew_point_c: 9.0)
        end

        visit admin_climate_dashboard_path(from: day.iso8601, to: day.iso8601)
        wait_for_charts

        banded = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']")
            .climateCharts[0].data.datasets.some((d) => d.band)
        JS
        assert_not banded
      end
    end
  end
end
