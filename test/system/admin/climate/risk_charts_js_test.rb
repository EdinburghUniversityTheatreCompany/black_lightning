require_relative "charts_system_test_case"

module Admin
  module Climate
    # Browser tests for the condensation-risk and ventilation charts: only a real
    # browser proves Chart.js plots the values it was handed, not a neighbouring column.
    class RiskChartsJsTest < ChartsSystemTestCase
      setup do
        @crypt = create_climate_sensor(display_name: "Crypt north", in_crypt: true)
        @outdoor = outdoor_climate_sensor
        seed_readings
      end

      # Distinct values per sensor and measure, so a chart plotting the wrong
      # series or column cannot pass. The crypt margin is 2.0 °C for four hours
      # and 4.0 °C for two, so at-risk hours are a strict subset of covered hours
      # and bars reading hours_with_readings fail.
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
        # 2.0 and 4.0 are the seeded margins, far from the 11.0 and 13.0 temperatures.
        assert_in_delta 2.0, values.min, 0.001
        assert_in_delta 4.0, values.max, 0.001
      end

      # The risk band is a plugin, not a dataset, so assert the plugin wiring
      # and the server's threshold rather than reading pixels.
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

      # Four of the six seeded hours are at risk, so the bars total FOUR; six
      # would mean the chart plots hours_with_readings.
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
    end
  end
end
