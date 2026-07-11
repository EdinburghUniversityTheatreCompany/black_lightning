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
        @actuals = actuals.sort_by { |a| a.imported_at || a.date&.to_time || Time.zone.at(0) }.reverse
      end
    end
  end
end
