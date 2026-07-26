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
      SHEETS = [
        [ Expenses, :expenses ],
        [ Actuals, :eusa_actuals ],
        [ Budgets, :budgets_with_actuals ],
        [ People, :people ],
        [ Batches, :batches ]
      ].freeze

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
        SHEETS.each do |exporter_class, collection_method|
          exporter = exporter_class.new(store: @store, checker: @checker)
          exporter.add_sheet(package.workbook, @store.public_send(collection_method))
        end
        package.to_stream.read
      end
    end
  end
end
