module Admin
  module Reimbursements
    ##
    # One download containing the whole portal: an xlsx with a sheet per
    # resource (Expenses, Actuals, Budgets, People, Batches), for the
    # end-of-run handover to EUSA, an accountant, or next year's committee —
    # the thing the per-view CSVs can't be, since each is one list at a time.
    #
    # Served inline from the request (the datasets are small in-memory arrays),
    # not emailed like the Reports::* spreadsheets.
    #
    # Bank details on the People sheet are masked to their last four digits;
    # only the BACS spreadsheet EUSA pays from carries full numbers.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class ExportsController < FinanceController
      # GET /admin/reimbursements/export — the PAGE, which says what the file
      # holds and lets the operator scope it before downloading.
      #
      # This was a sidebar link that silently downloaded a file: no sheet list,
      # no scope, and no way to choose one.
      def show
        @title = "Export"
        @sheets = ::Reimbursements::Exports::Workbook::SHEETS
        @counts = sheet_counts
      end

      # GET /admin/reimbursements/export/download — the file itself.
      #
      # A separate ACTION rather than a ?format=xlsx on #show, so no global
      # MIME registration is needed for one controller's download. It carries
      # the page's own ?year= and ?cost_centre=, so the file matches the page
      # the operator was looking at.
      def download
        workbook = ::Reimbursements::Exports::Workbook.new(store: store, checker: modulus_checker)
        send_data workbook.to_bytes,
                  type: ::Reimbursements::Exports::Workbook::CONTENT_TYPE,
                  filename: workbook.filename
      end

      private

      # How many rows each sheet would carry under the CURRENT scope, so the
      # page states what the download contains before the operator commits to
      # it — and so an empty sheet is visible as an empty sheet rather than
      # discovered in Excel.
      #
      # Off the store's already-memoized lists, which the page's own scope
      # built, so this costs the same reads the download would.
      def sheet_counts
        ::Reimbursements::Exports::Workbook::SHEETS.to_h do |exporter_class, collection_method|
          [ exporter_class::SHEET_NAME, store.public_send(collection_method).size ]
        end
      end
    end
  end
end
