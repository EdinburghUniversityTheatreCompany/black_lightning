require "test_helper"

module Admin
  module Climate
    class SensorsControllerTest < ActionController::TestCase
      include ClimateTestHelpers

      tests Admin::Climate::SensorsController

      setup do
        @original_builder = Admin::Climate::BaseController.govee_client_builder
        @user = FactoryBot.create(:user)
        grant_backend(@user)
        grant_climate_manage_permission(@user)
        sign_in @user
      end

      teardown do
        # Restore the seam on the SAME class it was written on, or it shadows
        # the default for the rest of the process.
        Admin::Climate::BaseController.govee_client_builder = @original_builder
      end

      def grant_backend(user)
        role = ::Role.find_by(name: "Backend") || ::Role.create!(name: "Backend").tap do |r|
          r.permissions << Admin::Permission.create(action: "access", subject_class: "backend")
        end
        user.add_role("Backend")
        role
      end

      def use_govee(fake)
        Admin::Climate::BaseController.govee_client_builder = -> { fake }
        fake
      end

      def device(external_id: "AA:BB:CC:DD:EE:FF", sku: "H5179", name: "Crypt north")
        ::Climate::GoveeClient::Device.new(external_id: external_id, sku: sku, name: name)
      end

      # --- index ---------------------------------------------------------------

      test "read permission alone cannot reach sensor configuration" do
        viewer = FactoryBot.create(:user)
        grant_backend(viewer)
        grant_climate_read_permission(viewer)
        sign_in viewer

        post :discover

        assert_response :forbidden
      end

      test "lists the sensors" do
        create_climate_sensor(display_name: "Crypt north")

        get :index

        assert_response :success
        assert_match "Crypt north", response.body
      end

      # --- discover ------------------------------------------------------------

      test "discover registers a new thermometer inactive and unverified" do
        use_govee(ClimateTestHelpers::FakeGovee.new(devices: [ device ]))

        assert_difference -> { ::Climate::Sensor.count }, 1 do
          post :discover
        end

        sensor = ::Climate::Sensor.govee.sole

        assert_equal "AA:BB:CC:DD:EE:FF", sensor.external_id
        assert_equal "Crypt north", sensor.display_name
        assert_not sensor.active?
        assert_not sensor.unit_verified?
      end

      test "discover is idempotent for a device already registered" do
        create_climate_sensor(external_id: "AA:BB:CC:DD:EE:FF")
        use_govee(ClimateTestHelpers::FakeGovee.new(devices: [ device ]))

        assert_no_difference -> { ::Climate::Sensor.count } do
          post :discover
        end
      end

      test "discover never overwrites an operator's settings on a known device" do
        sensor = create_climate_sensor(external_id: "AA:BB:CC:DD:EE:FF", display_name: "Crypt, north wall",
                                       temperature_unit: ::Climate::Sensor::UNIT_FAHRENHEIT, active: true)
        use_govee(ClimateTestHelpers::FakeGovee.new(devices: [ device(name: "H5179 Sensor") ]))

        post :discover
        sensor.reload

        assert_equal "Crypt, north wall", sensor.display_name
        assert_equal ::Climate::Sensor::UNIT_FAHRENHEIT, sensor.temperature_unit
        assert_predicate sensor, :active?
      end

      test "discover reports a Govee failure instead of blowing up" do
        use_govee(ClimateTestHelpers::FakeGovee.new(devices: ::Climate::GoveeClient::AuthError.new("bad key")))

        post :discover

        assert_redirected_to admin_climate_sensors_path
        assert_match(/could not reach govee/i, flash[:alert])
      end

      test "discover says so when the account has no thermometers" do
        use_govee(ClimateTestHelpers::FakeGovee.new(devices: []))

        post :discover

        assert_match(/no thermometers/i, flash[:notice])
      end

      # --- check_unit ----------------------------------------------------------

      test "check_unit shows the raw value read both ways" do
        sensor = create_climate_sensor(temperature_unit: nil)
        use_govee(ClimateTestHelpers::FakeGovee.new(
                    states: { sensor.external_id => ::Climate::GoveeClient::State.new(
                      raw_temperature: 53.6, relative_humidity: 78, online: true, fetched_at: Time.current
                    ) }
                  ))

        post :check_unit, params: { id: sensor.id }

        assert_response :success
        # 53.6 read as Celsius, or the 12.0 C it would be if that were Fahrenheit.
        assert_match "53.6", response.body
        assert_match "12.0", response.body
      end

      test "check_unit reports when Govee returns no temperature" do
        sensor = create_climate_sensor
        use_govee(ClimateTestHelpers::FakeGovee.new(
                    states: { sensor.external_id => ::Climate::GoveeClient::State.new(
                      raw_temperature: nil, relative_humidity: nil, online: true, fetched_at: Time.current
                    ) }
                  ))

        post :check_unit, params: { id: sensor.id }

        assert_redirected_to admin_climate_sensors_path
        assert_match(/no temperature/i, flash[:alert])
      end

      # --- update --------------------------------------------------------------

      test "update stamps the verification time when the unit is set" do
        sensor = create_climate_sensor(temperature_unit: nil)
        sensor.update_columns(unit_verified_at: nil)

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { temperature_unit: ::Climate::Sensor::UNIT_FAHRENHEIT } }
        sensor.reload

        assert_equal ::Climate::Sensor::UNIT_FAHRENHEIT, sensor.temperature_unit
        assert_not_nil sensor.unit_verified_at
      end

      test "update saves the operator-owned fields" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: "Crypt, north wall",
                                                   location: "Behind the bar", active: "1" } }
        sensor.reload

        assert_equal "Crypt, north wall", sensor.display_name
        assert_equal "Behind the bar", sensor.location
        assert_predicate sensor, :active?
      end

      test "update cannot change the device id, sku or source" do
        # Re-pointing a sensor at a different device would silently attach its
        # whole history to readings from somewhere else.
        sensor = create_climate_sensor(external_id: "AA:BB:CC:DD:EE:FF")

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: "Renamed",
                                                   external_id: "99:99:99:99:99:99",
                                                   sku: "H9999", source: "open_meteo" } }
        sensor.reload

        assert_equal "AA:BB:CC:DD:EE:FF", sensor.external_id
        assert_equal "H5179", sensor.sku
        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.source
      end

      test "update re-renders with errors on an invalid name" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id, climate_sensor: { display_name: "" } }

        assert_response :unprocessable_content
      end

      test "a read-only user cannot edit a sensor" do
        sensor = create_climate_sensor
        viewer = FactoryBot.create(:user)
        grant_backend(viewer)
        grant_climate_read_permission(viewer)
        sign_in viewer

        patch :update, params: { id: sensor.id, climate_sensor: { display_name: "Hijacked" } }

        assert_response :forbidden
        assert_not_equal "Hijacked", sensor.reload.display_name
      end
    end
  end
end
