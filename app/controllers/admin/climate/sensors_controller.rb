module Admin
  module Climate
    ##
    # Sensors are created by hand: the CSV export carries no device identifier,
    # so nothing can discover them.
    class SensorsController < BaseController
      before_action :authorize_climate_manage!, except: :index
      before_action :find_sensor, only: %i[edit update destroy]

      def index
        @title = "Climate Sensors"
        @sensors = ::Climate::Sensor.in_display_order.to_a
      end

      def new
        @title = "New sensor"
        @sensor = ::Climate::Sensor.new(source: ::Climate::Sensor::SOURCE_GOVEE,
                                        placement: ::Climate::Sensor::PLACEMENT_INDOOR,
                                        active: true)
      end

      def create
        @sensor = ::Climate::Sensor.new(sensor_params)
        @sensor.source = ::Climate::Sensor::SOURCE_GOVEE
        @sensor.placement = ::Climate::Sensor::PLACEMENT_INDOOR

        if @sensor.save
          redirect_to admin_climate_sensors_path, notice: "#{@sensor.display_name} added."
        else
          @title = "New sensor"
          render :new, status: :unprocessable_content
        end
      end

      def edit
        @title = "Edit #{@sensor.display_name}"
      end

      def update
        if @sensor.update(sensor_params)
          redirect_to admin_climate_sensors_path, notice: "#{@sensor.display_name} updated."
        else
          @title = "Edit #{@sensor.display_name}"
          render :edit, status: :unprocessable_content
        end
      end

      # Deleting takes the readings with it (dependent: :delete_all), which is
      # why the outdoor row, the one nobody can re-import, is not deletable.
      def destroy
        if @sensor.open_meteo?
          return redirect_to(admin_climate_sensors_path,
                             alert: "The outdoor feed cannot be deleted; deactivate it instead.")
        end

        count = @sensor.readings.count
        @sensor.destroy
        redirect_to admin_climate_sensors_path,
                    notice: "#{@sensor.display_name} deleted, along with #{helpers.pluralize(count, "reading")}."
      end

      private

      def find_sensor
        @sensor = ::Climate::Sensor.find(params[:id])
      end

      # source and placement are set by the controller, not the form: every
      # hand-made sensor is an indoor Govee one, and the outdoor row is ensured
      # in code. Letting a form set them would allow a second "outdoor" feed
      # that nothing polls.
      def sensor_params
        params.require(:climate_sensor).permit(:display_name, :location, :active, :position, :in_crypt)
      end
    end
  end
end
