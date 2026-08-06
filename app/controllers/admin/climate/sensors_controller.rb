module Admin
  module Climate
    ##
    # Sensor configuration: discover devices off the Govee account, name and
    # place them, and — the important one — verify which unit the API reports
    # temperature in before any reading is stored.
    class SensorsController < BaseController
      before_action :authorize_climate_manage!, only: %i[edit update discover check_unit]
      before_action :find_sensor, only: %i[edit update check_unit]

      def index
        @title = "Climate Sensors"
        @sensors = ::Climate::Sensor.in_display_order.to_a
      end

      def edit
        @title = "Edit #{@sensor.display_name}"
      end

      def update
        # So the dashboard can say when someone last confirmed it.
        if sensor_params[:temperature_unit].present? &&
           sensor_params[:temperature_unit] != @sensor.temperature_unit
          @sensor.unit_verified_at = Time.current
        end

        if @sensor.update(sensor_params)
          redirect_to admin_climate_sensors_path, notice: "#{@sensor.display_name} updated."
        else
          @title = "Edit #{@sensor.display_name}"
          render :edit, status: :unprocessable_content
        end
      end

      # New rows arrive INACTIVE and unit-unverified: a sensor is reviewed
      # before it starts writing history, and nobody hand-types a device id.
      def discover
        devices = govee_client.devices
        added = devices.count { |device| register(device) }

        redirect_to admin_climate_sensors_path,
                    notice: discovery_message(devices.size, added)
      rescue ::Climate::GoveeClient::Error => e
        redirect_to admin_climate_sensors_path,
                    alert: "Could not reach Govee: #{e.message}"
      end

      # The Fahrenheit question in the only terms that can settle it: the raw
      # number, what it means each way, go and look at the device.
      def check_unit
        state = govee_client.state(sku: @sensor.sku, external_id: @sensor.external_id)
        @raw = state.raw_temperature

        if @raw.nil?
          return redirect_to(admin_climate_sensors_path,
                             alert: "Govee returned no temperature for #{@sensor.display_name}.")
        end

        @as_celsius = @raw.to_f.round(1)
        @as_fahrenheit = ((@raw.to_f - 32.0) * 5.0 / 9.0).round(1)
        @title = "Verify #{@sensor.display_name}"
        render :check_unit
      rescue ::Climate::GoveeClient::Error => e
        redirect_to admin_climate_sensors_path, alert: "Could not reach Govee: #{e.message}"
      end

      private

      def find_sensor
        @sensor = ::Climate::Sensor.find(params[:id])
      end

      # external_id, sku and source come from discovery and must NOT be
      # editable: a changed device id re-points a sensor's whole history.
      def sensor_params
        params.require(:climate_sensor)
              .permit(:display_name, :location, :active, :temperature_unit, :position)
      end

      def register(device)
        sensor = ::Climate::Sensor.find_by(source: ::Climate::Sensor::SOURCE_GOVEE,
                                           external_id: device.external_id)
        return false if sensor.present?

        ::Climate::Sensor.create!(source: ::Climate::Sensor::SOURCE_GOVEE,
                                  external_id: device.external_id, sku: device.sku,
                                  display_name: device.name,
                                  # Both deliberately unset — see Climate::ReadingIngest.
                                  temperature_unit: nil, active: false)
        true
      end

      def discovery_message(found, added)
        return "Govee reports no thermometers on this account." if found.zero?

        if added.zero?
          "Found #{found} thermometer#{'s' if found != 1}, all already registered."
        else
          "Added #{added} new sensor#{'s' if added != 1}. Verify each one's temperature unit before activating it."
        end
      end
    end
  end
end
