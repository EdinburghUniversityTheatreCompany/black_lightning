module Reimbursements
  module Exports
    ##
    # The whole portal as one xlsx: a sheet per resource, built from the same
    # exporters that back the per-view "Download CSV" links, so a sheet and its
    # CSV can never disagree about a column.
    #
    # Sheet names are FIXED (never templated with a date): Excel caps a
    # worksheet name at 31 characters, and a formula in someone's own analysis
    # sheet that references 'Budgets'!D2 keeps working across every export.
    #
    # Bank details on the People sheet are masked to their last four digits —
    # see Exports::People. The BACS spreadsheet EUSA pays from is a different
    # artefact entirely (BacsXlsx) and still carries full numbers.
    #
    # Everything comes off the store's already-loaded lists, so the whole
    # workbook is built from one pass over the data the request loaded anyway.
    class Workbook
      CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

      # Sheet order = the order finance works in: the claims, then the EUSA
      # ledger they reconcile against, then the budgets they land on, then the
      # payee registry and the submission history.
      # The Budgets sheet carries the EUSA-actual rollup per line, so it reads the
      # actuals-preloaded list; every other caller of store.budgets deliberately
      # does not pay for that preload.
      #
      # EVERY sheet reads its cost-centre-scoped reader, so the workbook is one
      # coherent view: under ?cost_centre= the Budgets sheet was the only scoped
      # one, which left claims, ledger rows and batches from other pots sitting
      # beside budgets that could not account for them — the sheets no longer
      # added up to each other. With no centre selected every one of these
      # returns the whole portal, so the default download is unchanged.
      #
      # People is the exception and stays whole: a payee has no cost centre (see
      # Exports::People), and the same person claims from whichever pot their
      # claim's budget belongs to.
      SHEETS = [
        [ Expenses, :expenses_for_cost_centre ],
        [ Actuals, :eusa_actuals_for_cost_centre ],
        [ Budgets, :budgets_with_actuals ],
        [ Areas, :areas_for_year ],
        [ Forecasts, :forecasts_for_scope ],
        [ People, :people ],
        [ Batches, :batches_for_cost_centre ]
      ].freeze

      # The cover sheet's own name. Fixed like every other, and FIRST in the
      # workbook because what a reader needs before any figure is what the
      # figures cover.
      COVER_SHEET_NAME = "About this export".freeze

      def initialize(store:, checker: nil)
        @store = store
        @checker = checker
      end

      def filename(date: Date.current)
        "reimbursements-#{date.iso8601}.xlsx"
      end

      # The workbook as bytes, ready for send_data. The datasets are small
      # in-memory arrays, so building in-request is fine; if one ever grows
      # large, the Reports::* + ReportsMailer.deliver_later pattern is the
      # ready escape hatch.
      def to_bytes
        require "caxlsx" # lazy: kept out of the boot heap (Gemfile require:false)
        package = Axlsx::Package.new
        add_cover_sheet(package.workbook)
        SHEETS.each do |exporter_class, collection_method|
          exporter = exporter_class.new(store: @store, checker: @checker)
          exporter.add_sheet(package.workbook, @store.public_send(collection_method))
        end
        package.to_stream.read
      end

      # What this file covers, stated INSIDE it.
      #
      # Scope was mixed and unstated: Budgets followed the active year while
      # Expenses, Actuals, People and Batches were all of history, and nothing
      # in the file said so — a reader totalling a column had no way to know
      # which year or pot they were totalling. Now the scope is one workbook
      # wide, and this sheet records it, so a file found in a folder two years
      # later still explains itself.
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
          # A reader totalling one sheet against another has to know the scope
          # is not uniform: People has no cost centre at all, and only three
          # sheets read a year-scoped reader (see SHEETS).
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
