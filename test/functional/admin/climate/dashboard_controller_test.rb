require "test_helper"

module Admin
  module Climate
    class DashboardControllerTest < ActionController::TestCase
      include ClimateTestHelpers

      tests Admin::Climate::DashboardController

      # Graph::Settings reads GRAPH_* before the REIMBURSEMENTS_AZURE_* fallback; both are named so
      # that clearing them leaves nothing configured.
      GRAPH_ENV = %w[GRAPH REIMBURSEMENTS].product(%w[TENANT_ID CLIENT_ID CLIENT_SECRET])
                                          .to_h { |prefix, key| [ "#{prefix}_AZURE_#{key}", "x" ] }.freeze

      def with_env(vars)
        original = vars.keys.index_with { |key| ENV.fetch(key, nil) }
        vars.each { |key, value| ENV[key] = value }
        yield
      ensure
        original.each { |key, value| ENV[key] = value }
      end

      setup do
        @user = FactoryBot.create(:user)
        grant_backend(@user)
        grant_climate_read_permission(@user)
        sign_in @user
      end

      test "requires a signed-in user" do
        sign_out @user

        get :show

        assert_redirected_to new_user_session_path
      end

      test "denies a backend user without the climate permission" do
        other = FactoryBot.create(:user)
        grant_backend(other)
        sign_in other

        get :show

        assert_response :forbidden
      end

      test "honours from and to as readable url state" do
        get :show, params: { from: "2026-08-01", to: "2026-08-06" }

        assert_equal Date.new(2026, 8, 1), assigns(:range).from
        assert_equal Date.new(2026, 8, 6), assigns(:range).to
      end

      test "says so when a requested range had to be clamped" do
        # Never render a different range as though it were the one asked for.
        get :show, params: { from: "2026-08-06", to: "2026-08-01" }

        assert_response :success
        # The layout serialises flash into the SweetAlert payload and discards
        # it, so assert on the body.
        assert_match(/wrong way round/i, response.body)
      end

      test "shows only active sensors" do
        active = create_climate_sensor(display_name: "Live")
        create_climate_sensor(display_name: "Retired", active: false)

        get :show

        assert_equal [ active.id ], assigns(:sensors).map(&:id)
      end

      test "renders the current reading as text, not only in the chart" do
        sensor = create_climate_sensor(display_name: "Crypt north", location: "North wall")
        create_climate_reading(sensor: sensor, temperature_c: 11.5, relative_humidity: 88.0)

        get :show

        assert_match "Crypt north", response.body
        assert_match "North wall", response.body
        assert_match "11.5", response.body
        assert_match "88", response.body
        assert_match(/above the dew point/, response.body)
      end

      test "says so when there is nothing to plot yet" do
        create_climate_sensor

        get :show

        assert_match "No readings in this range yet", response.body
        assert_select "canvas[data-climate-charts-target]", 0
        assert_select "[data-controller='climate-charts']", 0
      end

      test "serves the page's series, margin, risk and ventilation as json" do
        sensor = create_climate_sensor(in_crypt: true)
        outdoor_climate_sensor
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show, format: :json
        payload = response.parsed_body

        assert_response :success
        assert_equal 2, payload["series"].size
        assert_equal 1, payload["series"].find { |series| series["id"] == sensor.id }["points"].size
        assert payload["range"]["from"].present?
        assert payload.key?("margin")
        assert payload.key?("risk")
        assert payload.key?("ventilation")
        assert_equal "worst", payload.dig("ventilation", "selected")
      end

      test "carries the Open-Meteo attribution the licence requires" do
        get :show

        assert_response :success
        assert_match(/Open-Meteo/, response.body)
      end

      test "mentions the daily email only when the poll job would actually run" do
        # The job needs the mailbox AND Graph credentials; copy promising an import it will
        # skip, or printing a blank address, is worse than saying nothing.
        with_env({ "CLIMATE_MAILBOX" => "climatesensors@example.com" }.merge(GRAPH_ENV)) do
          get :show

          assert_match "climatesensors@example.com", response.body
          assert_match(/daily report/i, response.body)
        end

        with_env({ "CLIMATE_MAILBOX" => "climatesensors@example.com" }.merge(GRAPH_ENV.transform_values { nil })) do
          get :show

          assert_no_match(/daily (report|email)/i, response.body)
          assert_match(/dressing room access point/i, response.body)
        end

        with_env({ "CLIMATE_MAILBOX" => nil }.merge(GRAPH_ENV)) do
          get :show

          assert_no_match(/daily (report|email)/i, response.body)
          assert_match(/dressing room access point/i, response.body)
        end
      end

      test "explains that the margin is measured against the air, not the walls" do
        # Every threshold is stated against the air, so the caveat must survive copy edits.
        get :show

        assert_match(/not the walls/i, response.body)
      end

      test "the crypt parameter selects which sensor the ventilation chart shows" do
        north = create_climate_sensor(display_name: "North", in_crypt: true)
        south = create_climate_sensor(display_name: "South", in_crypt: true)
        create_climate_reading(sensor: north, recorded_at: 2.hours.ago, temperature_c: 9.0)
        create_climate_reading(sensor: south, recorded_at: 2.hours.ago, temperature_c: 16.0)

        get :show, params: { crypt: south.id.to_s }

        assert_select "select#crypt option[selected][value=?]", south.id.to_s
      end

      test "an unknown crypt parameter falls back and says so" do
        create_climate_sensor(in_crypt: true)

        get :show, params: { crypt: "haddock" }

        assert_response :success
        assert_match(/not marked as being in the crypt/i, response.body)
      end

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

      test "offers every crypt sensor in the ventilation picker" do
        north = create_climate_sensor(display_name: "Crypt north", in_crypt: true)
        create_climate_reading(sensor: north, recorded_at: 2.hours.ago)

        get :show

        assert_match(/Coldest crypt sensor/, response.body)
        assert_match(/Crypt north/, response.body)
      end

      test "says the outside line is missing with no outdoor sensor, or one with no readings in range" do
        sensor = create_climate_sensor(in_crypt: true)
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show

        assert_match(/outside line is missing/, response.body)

        outdoor_climate_sensor
        get :show

        assert_match(/outside line is missing/, response.body)
      end
    end
  end
end
