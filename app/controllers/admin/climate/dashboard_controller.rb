module Admin
  module Climate
    ##
    # Risk and ventilation answers sit above the raw history charts that check them.
    class DashboardController < BaseController
      def show
        @title = "Crypt Climate"
        @sensors = ::Climate::Sensor.active.in_display_order.to_a
        @crypt_sensors = @sensors.select(&:in_crypt?)
        @outdoor_sensor = @sensors.find(&:outdoor?)
        @range = ::Climate::DateRange.from_params(params)

        build_series
        announce(@range.notice, @ventilation.notice)

        respond_to do |format|
          format.html
          # The page's own data, so the charts can be checked without reading pixels.
          format.json { render json: payload }
        end
      end

      private

      def build_series
        query = ::Climate::SeriesQuery.new(sensors: @sensors, range: @range)
        @series = query.series
        # A min-max band is meaningless at raw resolution.
        @banded = query.aggregated?

        @margin_series = ::Climate::MarginSeries.new(sensors: @crypt_sensors, range: @range).series
        @risk = ::Climate::RiskSummary.new(sensors: @crypt_sensors, range: @range).summaries
        @ventilation = ::Climate::VentilationSeries.new(crypt_sensors: @crypt_sensors,
                                                        outdoor_sensor: @outdoor_sensor,
                                                        range: @range, selected: params[:crypt])
      end

      # Both fall back rather than fail, so both have to SAY they fell back.
      def announce(*notices)
        said = notices.compact_blank
        flash.now[:notice] = said.join(" ") if said.any?
      end

      def payload
        { range: @range.as_json, series: @series, banded: @banded,
          margin: @margin_series, risk: @risk,
          ventilation: { selected: @ventilation.selected_key, series: @ventilation.series } }
      end
    end
  end
end
