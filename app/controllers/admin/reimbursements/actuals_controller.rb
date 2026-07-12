require "csv"

module Admin
  module Reimbursements
    ##
    # Read-only browser over the imported EUSA Actuals ledger (the rows created
    # by the Reconcile wizard). Finance can scan what's been imported, whether a
    # row is linked to an expense or an income budget, and filter by EUSA period.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`).
    class ActualsController < FinanceController
      def index
        @title = "EUSA Actuals"
        actuals = store.eusa_actuals
        @periods = actuals.map(&:period).reject(&:blank?).uniq.sort
        @period = params[:period].to_s.strip
        actuals = actuals.select { |a| a.period == @period } if @period.present?
        # Newest first: imported rows carry an imported_at; fall back to the
        # transaction date so hand-imported/legacy rows still sort sensibly.
        sorted = actuals.sort_by { |a| a.imported_at || a.date&.to_time || Time.zone.at(0) }.reverse
        respond_to do |format|
          format.html { @actuals = Kaminari.paginate_array(sorted).page(params[:page]).per(50) }
          # Export the FULL filtered set (the period filter carries through the
          # query string) — pagination is display-only, so the CSV isn't paged.
          format.csv do
            send_data actuals_csv(sorted), type: "text/csv",
                                           filename: "reimbursements-actuals-#{Date.current.iso8601}.csv"
          end
        end
      end

      private

      ACTUALS_CSV_HEADERS = [ "Date", "Type", "Description", "Amount", "Budget",
                              "Linked expense", "Period" ].freeze

      # The (period-filtered) actuals as a CSV string. A row's debit/credit
      # collapses to a Type + Amount pair; the linked expense/budget references
      # resolve to the expense's auto-number and the budget's name. Amounts stay
      # plain numbers so the export is spreadsheet-friendly; the date is ISO 8601.
      def actuals_csv(actuals)
        expenses_by_id = store.expenses.index_by(&:record_id)
        budgets_by_id = store.budgets.index_by(&:record_id)
        CSV.generate do |csv|
          csv << ACTUALS_CSV_HEADERS
          actuals.each do |actual|
            debit = actual.debit&.positive?
            csv << [
              helpers.reimbursements_date(actual.date),
              debit ? "Debit" : (actual.credit&.positive? ? "Credit" : ""),
              actual.narrative,
              debit ? actual.debit : actual.credit,
              budgets_by_id[actual.linked_budget_ids.first]&.name,
              expenses_by_id[actual.linked_expense_ids.first]&.auto_number,
              actual.period
            ]
          end
        end
      end
    end
  end
end
