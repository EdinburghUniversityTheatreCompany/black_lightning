module Admin
  module Reimbursements
    ##
    # One xlsx download of the whole portal, a sheet per resource, for the
    # end-of-run handover to EUSA, an accountant or next year's committee. Built
    # in the request (the datasets are small), not emailed like the Reports::*
    # spreadsheets. Finance-gated via FinanceController.
    class ExportsController < FinanceController
      # The page: says what the file holds and lets the operator scope it first.
      def show
        @title = "Export"
        @counts = ::Reimbursements::Exports::Workbook::SHEETS.to_h do |exporter_class, reader|
          [ exporter_class, store.public_send(reader).size ]
        end
      end

      # A separate action rather than ?format=xlsx on #show, so no global MIME
      # registration is needed. It carries the page's ?year= and ?cost_centre=,
      # so the file matches the page.
      def download
        workbook = ::Reimbursements::Exports::Workbook.new(store: store, checker: modulus_checker)
        send_data workbook.to_bytes,
                  type: ::Reimbursements::Exports::Workbook::CONTENT_TYPE,
                  filename: workbook.filename
      end
    end
  end
end
