require "test_helper"

module Admin
  module Climate
    class ImportsControllerTest < ActionController::TestCase
      include ClimateTestHelpers

      tests Admin::Climate::ImportsController

      EXPORT = "﻿Timestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity\n" \
               "2026-08-06 09:22:00,14.6,83.7\n" \
               "2026-08-06 09:37:00,14.4,84.1\n".freeze

      setup do
        @user = FactoryBot.create(:user)
        grant_backend(@user)
        grant_climate_manage_permission(@user)
        sign_in @user
        @sensor = create_climate_sensor(display_name: "Crypt north")
      end

      def grant_backend(user)
        role = ::Role.find_by(name: "Backend") || ::Role.create!(name: "Backend").tap do |r|
          r.permissions << Admin::Permission.create(action: "access", subject_class: "backend")
        end
        user.add_role("Backend")
        role
      end

      def upload(text, filename: "export.csv")
        Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: filename)
      end

      test "shows the form" do
        get :new

        assert_response :success
      end

      test "imports an uploaded file" do
        assert_difference -> { @sensor.readings.count }, 2 do
          post :create, params: { sensor_id: @sensor.id, file: upload(EXPORT) }
        end
      end

      test "stores the readings against the chosen sensor" do
        other = create_climate_sensor(display_name: "Crypt south")

        post :create, params: { sensor_id: other.id, pasted_text: EXPORT }

        assert_equal 2, other.readings.count
        assert_equal 0, @sensor.readings.count
      end

      test "refuses without a sensor, and the outdoor feed as an import target" do
        # The outdoor feed is fed hourly from Open-Meteo; a hand-imported crypt
        # file landing there would corrupt the comparison line.
        [ nil, outdoor_climate_sensor.id ].each do |sensor_id|
          assert_no_difference -> { ::Climate::Reading.count } do
            post :create, params: { sensor_id: sensor_id, pasted_text: EXPORT }
          end

          assert_response :unprocessable_content
          assert_match(/pick which sensor/i, response.body)
        end
      end

      test "refuses an empty submission" do
        post :create, params: { sensor_id: @sensor.id, pasted_text: "" }

        assert_response :unprocessable_content
        assert_match(/choose a csv/i, response.body)
      end

      test "refuses a file whose unit it cannot identify" do
        post :create, params: { sensor_id: @sensor.id,
                                pasted_text: "Timestamp,Temperature,Relative_Humidity\n2026-08-06 09:22:00,14.6,83.7\n" }

        assert_response :unprocessable_content
        assert_match(/unit/i, response.body)
        assert_equal 0, @sensor.readings.count
      end

      test "ignores a string sent in place of a file upload" do
        # The duck-typed guard: params[:file] as a plain String must not reach #read.
        post :create, params: { sensor_id: @sensor.id, file: "not-a-file", pasted_text: EXPORT }

        assert_response :success
        assert_equal 2, @sensor.readings.count
      end

      test "a read-only user cannot import" do
        viewer = FactoryBot.create(:user)
        grant_backend(viewer)
        grant_climate_read_permission(viewer)
        sign_in viewer

        post :create, params: { sensor_id: @sensor.id, pasted_text: EXPORT }

        assert_response :forbidden
        assert_equal 0, @sensor.readings.count
      end
    end
  end
end
