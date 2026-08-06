module Admin
  module Climate
    ##
    # Importing a Govee CSV export.
    #
    # Deliberately one step rather than the preview-then-apply wizard the budget
    # import uses. There are no per-row decisions to make, a two-year backfill is
    # tens of thousands of rows (far past what a hidden-field round trip can
    # carry), and re-importing is harmless because the unique index dedups. The
    # one consequential choice — which sensor the file belongs to — is made
    # before the upload, not after.
    #
    # This is also the exact path an automated mailbox ingest calls, so the
    # manual and automatic routes cannot drift.
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
