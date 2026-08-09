module Admin
  module Climate
    ##
    # Answer first, evidence second: the condensation-risk and ventilation
    # views render above the raw history charts, which exist to check them
    # against.
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
          # Served for the same data the page draws, so the charts can be
          # checked without reading pixels off a canvas.
          format.json { render json: payload }
        end
      end

      private

      def build_series
        query = ::Climate::SeriesQuery.new(sensors: @sensors, range: @range)
        @series = query.series
        # A min-max band means nothing until a bucket holds more than one
        # reading, and would draw as a zero-width artefact at raw resolution.
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
