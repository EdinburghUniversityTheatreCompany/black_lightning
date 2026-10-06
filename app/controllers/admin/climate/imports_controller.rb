module Admin
  module Climate
    ##
    # Importing a Govee CSV export. One step, not a preview wizard: there are no
    # per-row decisions, a two-year backfill is far past what a hidden-field round
    # trip carries, and re-importing is harmless. The one real choice, which
    # sensor, is made before the upload.
    class ImportsController < BaseController
      before_action :authorize_climate_manage!
      before_action :load_sensors

      def new; end

      def create
        @sensor = @sensors.find { |sensor| sensor.id.to_s == params[:sensor_id].to_s }
        return reject("Pick which sensor this file came from.") if @sensor.nil?

        text = import_text
        return reject("Choose a CSV file, or paste its contents.") if text.blank?

        @import = ::Climate::CsvImport.new(text)
        return reject(@import.errors.to_sentence) unless @import.valid?

        @result = ::Climate::ReadingIngest.upsert_series!(sensor: @sensor, rows: @import.rows)
        @title = "Imported"
      end

      private

      def load_sensors
        @title = "Import readings"
        @sensors = ::Climate::Sensor.govee.in_display_order.to_a
      end

      def reject(message)
        flash.now[:alert] = message
        render :new, status: :unprocessable_content
      end

      def import_text = uploaded_file ? uploaded_file.read : params[:pasted_text].to_s

      # Duck-typed so a crafted string param for :file cannot reach #read.
      def uploaded_file
        file = params[:file]
        file.respond_to?(:read) ? file : nil
      end
    end
  end
end
