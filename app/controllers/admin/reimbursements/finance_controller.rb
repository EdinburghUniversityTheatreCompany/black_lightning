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

      # A submitted Airtable link-field id (budget_record_id, owner_ids) must
      # resolve to a real, known record before writing the link — none of the
      # write paths that touch these link fields validated this before;
      # Airtable's own API rejects an unknown linked-record id with an error,
      # which would otherwise surface as an unhandled 500 instead of a
      # friendly flash pointing at what to fix.
      def budget_record_id_error(record_id)
        return nil if record_id.blank?
        return nil if store.find_budget(record_id)

        "That budget no longer exists — please pick another."
      end

      def owner_ids_error(record_ids)
        unknown = Array(record_ids).reject(&:blank?).reject { |id| store.find_person(id) }
        return nil if unknown.empty?

        "One or more selected owners no longer exist — please update the list."
      end
    end
  end
end
