module Admin
  module Climate
    ##
    # The three charts (temperature, relative humidity, dew point) plus the
    # current-readings tiles.
    class DashboardController < BaseController
      def show
        @title = "Crypt Climate"
        @sensors = ::Climate::Sensor.active.in_display_order.to_a
        @range = ::Climate::DateRange.from_params(params)
        flash.now[:notice] = @range.notice if @range.notice.present?

        @series = ::Climate::SeriesQuery.new(sensors: @sensors, range: @range).series

        respond_to do |format|
          format.html
          # Served for the same data the page draws, so the charts can be
          # checked without reading pixels off a canvas.
          format.json { render json: { range: @range.as_json, series: @series } }
        end
      end
    end
  end
end
