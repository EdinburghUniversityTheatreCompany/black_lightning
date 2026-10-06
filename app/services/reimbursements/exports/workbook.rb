module Reimbursements
  module Exports
    ##
    # The whole portal as one xlsx, a sheet per resource, built from the same
    # exporters as the per-view "Download CSV" links so a sheet and its CSV
    # cannot disagree about a column.
    class Workbook
      CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

      # Budgets reads the actuals-preloaded list for its EUSA-actual rollup; no
      # other caller of store.budgets pays for that preload.
      #
      # Every sheet reads its cost-centre-scoped reader, so the sheets add up to
      # each other (with no centre selected each returns the whole portal).
      # People is the exception: a payee has no cost centre.
      SHEETS = [
        [ Expenses, :expenses_for_cost_centre ],
        [ Actuals, :eusa_actuals_for_cost_centre ],
        [ Budgets, :budgets_with_actuals ],
        [ Areas, :areas_for_year ],
        [ Forecasts, :forecasts_for_scope ],
        [ People, :people ],
        [ Batches, :batches_for_cost_centre ]
      ].freeze

      # FIRST in the workbook: a reader needs what the figures cover before any figure.
      COVER_SHEET_NAME = "About this export".freeze

      def initialize(store:, checker: nil)
        @store = store
        @checker = checker
      end

      def filename(date: Date.current)
        "reimbursements-#{date.iso8601}.xlsx"
      end

      def to_bytes
        require "caxlsx" # lazy: the Gemfile has require: false
        package = Axlsx::Package.new
        add_cover_sheet(package.workbook)
        SHEETS.each do |exporter_class, collection_method|
          exporter = exporter_class.new(store: @store, checker: @checker)
          exporter.add_sheet(package.workbook, @store.public_send(collection_method))
        end
        package.to_stream.read
      end

      # What this file covers, stated INSIDE it, so a file found in a folder
      # years later still explains itself.
      def add_cover_sheet(workbook)
        workbook.add_worksheet(name: COVER_SHEET_NAME) do |sheet|
          cover_rows.each { |row| sheet.add_row(row, types: [ :string, :string ]) }
        end
      end

      def cover_rows
        [
          [ "Exported", Date.current.iso8601 ],
          [ "Financial year", @store.financial_year&.label || "Every year" ],
          [ "Cost centre", @store.cost_centre&.name || "Every cost centre" ],
          [ "Sheets", SHEETS.map { |exporter_class, _| exporter_class::SHEET_NAME }.join(", ") ],
          [ "Note", "The cost centre covers every sheet except People, which has none. The " \
                    "year covers Budgets, Areas and Forecast revisions only; Claims, the " \
                    "ledger and Batches cover every year." ],
          [ "Bank details", "Masked to the last four digits. Only the BACS spreadsheet EUSA is " \
                            "paid from carries full numbers." ]
        ]
      end
    end
  end
end
