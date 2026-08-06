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

      def grant_backend(user)
        role = ::Role.find_by(name: "Backend") || ::Role.create!(name: "Backend").tap do |r|
          r.permissions << Admin::Permission.create(action: "access", subject_class: "backend")
        end
        user.add_role("Backend")
        role
      end

      def sign_in_read_only
        viewer = FactoryBot.create(:user)
        grant_backend(viewer)
        grant_climate_read_permission(viewer)
        sign_in viewer
        viewer
      end

      # --- index -----------------------------------------------------------

      test "lists the sensors" do
        create_climate_sensor(display_name: "Crypt north")

        get :index

        assert_response :success
        assert_match "Crypt north", response.body
      end

      test "a read-only user may look at the list" do
        sign_in_read_only

        get :index

        assert_response :success
      end

      # --- create ----------------------------------------------------------

      test "creates a sensor" do
        assert_difference -> { ::Climate::Sensor.count }, 1 do
          post :create, params: { climate_sensor: { display_name: "Crypt south",
                                                    location: "By the stairs", active: "1" } }
        end

        sensor = ::Climate::Sensor.order(:id).last

        assert_equal "Crypt south", sensor.display_name
        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.source
        assert_equal ::Climate::Sensor::PLACEMENT_INDOOR, sensor.placement
      end

      test "a form cannot smuggle in a second outdoor feed" do
        # source and placement are controller-set. A second "outdoor" row would
        # be polled by nothing and would sit dead on the dashboard.
        post :create, params: { climate_sensor: { display_name: "Fake outside",
                                                  source: "open_meteo", placement: "outdoor" } }
        sensor = ::Climate::Sensor.order(:id).last

        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.source
        assert_equal ::Climate::Sensor::PLACEMENT_INDOOR, sensor.placement
      end

      test "re-renders when the name is missing" do
        assert_no_difference -> { ::Climate::Sensor.count } do
          post :create, params: { climate_sensor: { display_name: "" } }
        end

        assert_response :unprocessable_content
      end

      test "a read-only user cannot create a sensor" do
        sign_in_read_only

        assert_no_difference -> { ::Climate::Sensor.count } do
          post :create, params: { climate_sensor: { display_name: "Sneaky" } }
        end

        assert_response :forbidden
      end

      # --- update ----------------------------------------------------------

      test "updates the operator-owned fields" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: "Crypt, north wall",
                                                   location: "Behind the bar", active: "1" } }
        sensor.reload

        assert_equal "Crypt, north wall", sensor.display_name
        assert_equal "Behind the bar", sensor.location
      end

      test "update cannot change how a sensor is fed" do
        sensor = create_climate_sensor

        patch :update, params: { id: sensor.id,
                                 climate_sensor: { display_name: "Renamed", source: "open_meteo" } }

        assert_equal ::Climate::Sensor::SOURCE_GOVEE, sensor.reload.source
      end

      test "a read-only user cannot edit a sensor" do
        sensor = create_climate_sensor
        sign_in_read_only

        patch :update, params: { id: sensor.id, climate_sensor: { display_name: "Hijacked" } }

        assert_response :forbidden
        assert_not_equal "Hijacked", sensor.reload.display_name
      end

      # --- destroy ---------------------------------------------------------

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

      test "a read-only user cannot delete a sensor" do
        sensor = create_climate_sensor
        sign_in_read_only

        assert_no_difference -> { ::Climate::Sensor.count } do
          delete :destroy, params: { id: sensor.id }
        end

        assert_response :forbidden
      end
    end
  end
end
