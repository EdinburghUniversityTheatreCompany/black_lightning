module Admin
  module Climate
    ##
    # Importing a Govee CSV export.
    #
    # One step, not the budget import's preview-then-apply wizard: no per-row
    # decisions exist, a two-year backfill is far past what a hidden-field round
    # trip carries, and re-importing is harmless. The one consequential choice —
    # which sensor — is made before the upload.
    #
    # It is also the exact path the mailbox ingest calls, so the two cannot drift.
    class ImportsController < BaseController
      before_action :authorize_climate_manage!

      def new
        @title = "Import readings"
        @sensors = ::Climate::Sensor.govee.in_display_order.to_a
      end

      def create
        @sensors = ::Climate::Sensor.govee.in_display_order.to_a
        @sensor = ::Climate::Sensor.govee.find_by(id: params[:sensor_id])
        return reject("Pick which sensor this file came from.") if @sensor.nil?

        text = import_text
        return reject("Choose a CSV file, or paste its contents.") if text.blank?

        @import = ::Climate::CsvImport.new(text)
        return reject(@import.errors.to_sentence) unless @import.valid?

        @result = ::Climate::ReadingIngest.upsert_series!(sensor: @sensor, rows: @import.rows)
        @title = "Imported"
        render :create
      end

      private

      def reject(message)
        @title = "Import readings"
        flash.now[:alert] = message
        render :new, status: :unprocessable_content
      end

      def import_text
        return uploaded_file.read.dup.force_encoding(Encoding::UTF_8) if uploaded_file

        params[:pasted_text].to_s
      end

      # Duck-typed rather than a class check, so a crafted request sending a
      # plain string for :file cannot reach #read.
      def uploaded_file
        file = params[:file]
        file.respond_to?(:read) ? file : nil
      end
    end
  end
end
