require "test_helper"

module Admin
  module Climate
    class SensorsControllerTest < ActionController::TestCase
      include ClimateTestHelpers

      tests Admin::Climate::SensorsController

      setup do
        @user = FactoryBot.create(:user)
        grant_backend(@user)
        grant_climate_manage_permission(@user)
        sign_in @user
      end

      def sign_in_read_only
        viewer = FactoryBot.create(:user)
        grant_backend(viewer)
        grant_climate_read_permission(viewer)
        sign_in viewer
        viewer
      end

      test "lists the sensors, for a read-only user too" do
        create_climate_sensor(display_name: "Crypt north")
        sign_in_read_only

        get :index

        assert_response :success
        assert_match "Crypt north", response.body
      end

      test "creates an indoor Govee sensor whatever source and placement the form posts" do
        # A second "outdoor" row would be polled by nothing.
        assert_difference -> { ::Climate::Sensor.count }, 1 do
          post :create, params: { climate_sensor: { display_name: "Crypt south", location: "By the stairs",
                                                    active: "1", source: "open_meteo", placement: "outdoor" } }
        end

        sensor = ::Climate::Sensor.order(:id).last

        assert_equal "Crypt south", sensor.display_name
        assert_equal "By the stairs", sensor.location
        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.source
        assert_equal ::Climate::Sensor::PLACEMENT_INDOOR, sensor.placement
      end

      test "re-renders when the name is missing" do
        assert_no_difference -> { ::Climate::Sensor.count } do
          post :create, params: { climate_sensor: { display_name: "" } }
        end

        assert_response :unprocessable_content
      end

      test "updates the operator-owned fields but not how a sensor is fed" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: "Crypt, north wall", location: "Behind the bar",
                                                   in_crypt: "1", source: "open_meteo" } }
        sensor.reload

        assert_equal "Crypt, north wall", sensor.display_name
        assert_equal "Behind the bar", sensor.location
        assert_predicate sensor, :in_crypt?
        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.source
      end

      test "a read-only user cannot create, edit or delete a sensor" do
        sensor = create_climate_sensor
        sign_in_read_only

        [ [ :post, :create, { climate_sensor: { display_name: "x" } } ],
          [ :patch, :update, { id: sensor.id, climate_sensor: { display_name: "x" } } ],
          [ :delete, :destroy, { id: sensor.id } ] ].each do |verb, action, params|
          assert_no_difference -> { ::Climate::Sensor.count } do
            send(verb, action, params: params)
          end

          assert_response :forbidden, action.to_s
        end

        assert_not_equal "x", sensor.reload.display_name
      end

      test "deleting a sensor takes its readings with it" do
        sensor = create_climate_sensor
        create_climate_reading(sensor: sensor)

        assert_difference -> { ::Climate::Reading.count }, -1 do
          delete :destroy, params: { id: sensor.id }
        end
      end

      test "the outdoor feed cannot be deleted" do
        # Its readings are the one series nobody can re-import by hand.
        outdoor = outdoor_climate_sensor

        assert_no_difference -> { ::Climate::Sensor.count } do
          delete :destroy, params: { id: outdoor.id }
        end

        assert_match(/cannot be deleted/i, flash[:alert])
      end

      test "only a Govee sensor's edit form offers the In the crypt box" do
        # Ticking it on the outdoor row always fails validation.
        get :edit, params: { id: create_climate_sensor.id }

        assert_select "input[type=checkbox][name='climate_sensor[in_crypt]']", 1

        get :edit, params: { id: outdoor_climate_sensor.id }

        assert_response :success
        assert_select "input[type=checkbox][name='climate_sensor[active]']", 1
        assert_select "input[name='climate_sensor[in_crypt]']", 0
      end
    end
  end
end
