require "application_system_test_case"

module Admin
  module Climate
    # Browser tests for the three charts. The functional tests prove the ERB
    # renders and the payload is right; only a real browser proves Chart.js
    # actually draws, that it plots the values it was given, and that the
    # charts are torn down on navigation.
    #
    # Chart.js is imported as an ES module, so there is no window.Chart to
    # inspect — the controller exposes its instances on the element instead.
    class ChartsJsTest < ApplicationSystemTestCase
      include ClimateTestHelpers

      setup do
        role = ::Role.create!(name: "Climate Viewer")
        role.permissions << ::Admin::Permission.create(action: "read", subject_class: "climate")
        role.permissions << ::Admin::Permission.create(action: "access", subject_class: "backend")
        users(:member).add_role("Climate Viewer")
        login_as users(:member)

        @sensor = create_climate_sensor(display_name: "Crypt north", location: "North wall")
        @outdoor = outdoor_climate_sensor
        seed_readings
      end

      # Deliberately distinct values per sensor and per measure, so a chart
      # plotting the wrong series or the wrong column cannot pass.
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

      # chart_index: 0 temperature, 1 humidity, 2 dew point.
      #
      # Excludes band datasets: once a range is banded, the min and max band
      # datasets share the SAME label as the line they shade, so a bare label
      # match can return the band's max line instead of the actual plotted line.
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

      test "draws all three charts" do
        visit admin_climate_dashboard_path
        wait_for_charts

        assert_selector "canvas[data-climate-charts-target='temperature']"
        assert_selector "canvas[data-climate-charts-target='humidity']"
        assert_selector "canvas[data-climate-charts-target='dewPoint']"
      end

      test "the temperature chart plots each sensor's own temperatures" do
        visit admin_climate_dashboard_path
        wait_for_charts

        indoor = plotted(0, "Crypt north")
        outside = plotted(0, @outdoor.display_name)

        # Hourly buckets average the two readings in each hour.
        assert_equal [ 11.05, 11.25, 11.45, 11.65, 11.85, 12.05 ], indoor
        assert_equal [ 17.05, 17.25, 17.45, 17.65, 17.85, 18.05 ], outside
      end

      test "the humidity chart plots humidity, not temperature" do
        visit admin_climate_dashboard_path
        wait_for_charts

        assert_equal [ 85.0 ] * 6, plotted(1, "Crypt north")
        assert_equal [ 65.0 ] * 6, plotted(1, @outdoor.display_name)
      end

      test "the dew point chart plots dew point" do
        visit admin_climate_dashboard_path
        wait_for_charts

        assert_equal [ 9.0 ] * 6, plotted(2, "Crypt north")
        assert_equal [ 10.0 ] * 6, plotted(2, @outdoor.display_name)
      end

      test "the outdoor line is dashed so it reads apart from the sensors" do
        visit admin_climate_dashboard_path
        wait_for_charts

        # Band datasets carry no borderDash at all (they are filled shading,
        # not a stroke), so they have to be excluded here the same way
        # #plotted excludes them by label.
        dashes = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']").climateCharts[0]
            .data.datasets.filter(d => !d.band).map(d => ({ label: d.label, dash: d.borderDash.length }))
        JS

        assert_operator dashes.find { |d| d["label"] == @outdoor.display_name }["dash"], :>, 0
        assert_equal 0, dashes.find { |d| d["label"] == "Crypt north" }["dash"]
      end

      test "lines break across a gap rather than interpolating through it" do
        # spanGaps false plus the server's explicit null points is what stops a
        # two-day outage being drawn as a straight, entirely invented line.
        # Band datasets carry the same (also-false) spanGaps for the same
        # reason, so every dataset is asserted here, not just the two lines.
        visit admin_climate_dashboard_path
        wait_for_charts

        span_gaps = evaluate_script(<<~JS)
          document.querySelector("[data-controller='climate-charts']").climateCharts[0]
            .data.datasets.map(d => d.spanGaps)
        JS

        assert_operator span_gaps.length, :>, 0
        assert_equal [ false ] * span_gaps.length, span_gaps
      end

      test "the current readings are real text, not only pixels on a canvas" do
        visit admin_climate_dashboard_path

        assert_text "Crypt north"
        assert_text "North wall"
        assert_text(/above the dew point/)
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

      test "charts are destroyed on navigation away rather than leaking" do
        visit admin_climate_dashboard_path
        wait_for_charts

        visit admin_path

        assert_no_selector "[data-climate-charts-ready]"
      end

      test "says so when there is nothing to plot yet" do
        ::Climate::Reading.delete_all

        visit admin_climate_dashboard_path

        assert_text "No readings in this range yet"
        assert_no_selector "canvas[data-climate-charts-target='temperature']"
      end
    end
  end
end
