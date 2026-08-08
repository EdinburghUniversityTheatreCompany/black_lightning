require "test_helper"

module Admin
  module Climate
    class DashboardControllerTest < ActionController::TestCase
      include ClimateTestHelpers

      tests Admin::Climate::DashboardController

      setup do
        @user = FactoryBot.create(:user)
        grant_backend_and_climate_read(@user)
        sign_in @user
      end

      def grant_backend_and_climate_read(user)
        role = ::Role.find_by(name: "Climate Viewer") || ::Role.create!(name: "Climate Viewer").tap do |r|
          r.permissions << Admin::Permission.create(action: "read", subject_class: "climate")
          r.permissions << Admin::Permission.create(action: "access", subject_class: "backend")
        end
        user.add_role("Climate Viewer")
        role
      end

      test "requires a signed-in user" do
        sign_out @user

        get :show

        assert_redirected_to new_user_session_path
      end

      test "denies a backend user without the climate permission" do
        other = FactoryBot.create(:user)
        role = ::Role.create!(name: "Backend Only")
        role.permissions << Admin::Permission.create(action: "access", subject_class: "backend")
        other.add_role("Backend Only")
        sign_in other

        get :show

        assert_response :forbidden
      end

      test "renders for a user with the climate read permission" do
        create_climate_sensor

        get :show

        assert_response :success
      end

      test "defaults to the last seven days" do
        get :show

        assert_equal Date.current, assigns(:range).to
        assert_equal Date.current - 6.days, assigns(:range).from
      end

      test "honours from and to as readable url state" do
        get :show, params: { from: "2026-08-01", to: "2026-08-06" }

        assert_equal Date.new(2026, 8, 1), assigns(:range).from
        assert_equal Date.new(2026, 8, 6), assigns(:range).to
      end

      test "says so when a requested range had to be clamped" do
        # Never silently render a different range as though it were the one
        # asked for. That is how last week's damp gets read as this week's.
        get :show, params: { from: "2026-08-06", to: "2026-08-01" }

        assert_response :success
        # The layout serialises flash into the SweetAlert payload and then
        # discards it, so the rendered body is where the message actually is.
        assert_match(/wrong way round/i, response.body)
      end

      test "shows only active sensors" do
        active = create_climate_sensor(display_name: "Live")
        create_climate_sensor(display_name: "Retired", active: false)

        get :show

        assert_equal [ active.id ], assigns(:sensors).map(&:id)
      end

      test "renders the current reading as text, not only in the chart" do
        sensor = create_climate_sensor(display_name: "Crypt north")
        create_climate_reading(sensor: sensor, temperature_c: 11.5, relative_humidity: 88.0)

        get :show

        assert_match "Crypt north", response.body
        assert_match "11.5", response.body
        assert_match "88", response.body
      end

      test "serves the same series as json" do
        sensor = create_climate_sensor
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show, format: :json
        body = response.parsed_body

        assert_response :success
        assert_equal 1, body["series"].size
        assert_equal 1, body["series"].first["points"].size
        assert body["range"]["from"].present?
      end

      test "downsamples a long range instead of shipping every reading" do
        sensor = create_climate_sensor
        200.times do |index|
          create_climate_reading(sensor: sensor,
                                 recorded_at: Time.zone.parse("2026-08-01 00:00") + (index * 10).minutes)
        end

        get :show, format: :json, params: { from: "2025-08-06", to: "2026-08-06" }
        points = response.parsed_body["series"].first["points"]

        assert_operator points.size, :<, 10
      end

      test "renders with no sensors at all" do
        get :show

        assert_response :success
      end

      test "carries the Open-Meteo attribution the licence requires" do
        get :show

        assert_match(/Open-Meteo/, response.body)
      end

      test "mentions the daily email only when a climate mailbox is configured" do
        # The copy claims a report arrives automatically. That is a lie in an
        # environment with no mailbox set, and it would render a blank address.
        original = ENV.fetch("CLIMATE_MAILBOX", nil)
        ENV["CLIMATE_MAILBOX"] = "climatesensors@example.com"

        get :show

        assert_match "climatesensors@example.com", response.body
        assert_match(/daily report/i, response.body)

        ENV.delete("CLIMATE_MAILBOX")
        get :show

        assert_no_match(/daily report/i, response.body)
        assert_match(/out of Wi-Fi range/i, response.body)
      ensure
        original.nil? ? ENV.delete("CLIMATE_MAILBOX") : ENV["CLIMATE_MAILBOX"] = original
      end

      test "explains that the margin is measured against the air, not the walls" do
        # Every threshold in this copy is stated against a number we do not
        # measure, so the caveat has to survive future edits.
        get :show

        assert_match(/not the walls/i, response.body)
      end

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
        # As with the date-range clamp above: the layout serialises flash.now
        # into the SweetAlert payload (merging :notice into :success) and
        # discards it, so the rendered body is where the message survives,
        # not a bare flash.now[:notice] read after the request completes.
        assert_match(/not marked as being in the crypt/i, response.body)
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

      test "says the outside line is missing when there is no outdoor sensor" do
        sensor = create_climate_sensor(in_crypt: true)
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

        get :show

        assert_match(/outside line is missing/, response.body)
      end

      test "says the outside line is missing when the outdoor sensor has no readings in range" do
        sensor = create_climate_sensor(in_crypt: true)
        create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)
        outdoor_climate_sensor

        get :show

        assert_match(/outside line is missing/, response.body)
      end
    end
  end
end
