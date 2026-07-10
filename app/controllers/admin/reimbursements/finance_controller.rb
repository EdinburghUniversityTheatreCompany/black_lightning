module Admin
  module Reimbursements
    ##
    # Base for the finance-team operator surfaces (People, Review, Batches,
    # Reconcile, Settings). These are gated by the finance grid permission
    # (`:manage, :reimbursements_finance`) instead of the producer portal's
    # `:access, :reimbursements`, so a plain submitter can't reach them.
    class FinanceController < BaseController
      skip_before_action :authorize_reimbursements!
      before_action :authorize_finance!

      private

      def authorize_finance!
        authorize! :manage, :reimbursements_finance
      end
    end
  end
end
