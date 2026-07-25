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
      # GET /admin/reimbursements/export
      def show
        workbook = ::Reimbursements::Exports::Workbook.new(store: store, checker: modulus_checker)
        send_data workbook.to_bytes,
                  type: ::Reimbursements::Exports::Workbook::CONTENT_TYPE,
                  filename: workbook.filename
      end
    end
  end
end
