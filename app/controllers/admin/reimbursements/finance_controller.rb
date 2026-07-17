module Admin
  module Reimbursements
    ##
    # Base for the finance-team operator surfaces (People, Review, Batches,
    # Reconcile, Settings). These are gated by the finance grid permission
    # (`:manage, :reimbursements_finance`) instead of the producer portal's
    # `:access, :reimbursements`, so a plain submitter can't reach them.
    class FinanceController < BaseController
      include ::Reimbursements::ErrorReporting

      skip_before_action :authorize_reimbursements!
      before_action :authorize_finance!

      # Injection seam for tests: the modulus checker (from the vendored Pay.UK
      # rule files in production; a fake in functional tests). Shared by every
      # subclass that shows/validates a bank-detail modulus badge.
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      # Injection seam for tests: the app-only Graph client (SharePoint browse,
      # deleting a stale EUSA draft). Shared by every subclass that talks to
      # Graph directly from the request (not the jobs, which build their own
      # per-run instance for OAuth-token-reuse reasons — see
      # BuildBatchJob/NightlyBatchJob's own memoized +graph+).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      helper_method :modulus_checker

      # A page of records for an index view. One shared page size (50) across
      # every finance list, so a future change to it is a single edit.
      PAGE_SIZE = 50

      private

      def authorize_finance!
        authorize! :manage, :reimbursements_finance
      end

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def graph
        @graph ||= graph_builder.call
      end

      # Fetches via +store.public_send(finder, id)+, raising the standard 404
      # the framework already renders when it's not found — the shared body of
      # every "look up one record by params[:id], 404 if it's gone" action.
      def find_or_404(finder, id = params[:id])
        store.public_send(finder, id) || raise(ActiveRecord::RecordNotFound)
      end

      def find_expense!
        find_or_404(:find_expense!)
      end

      def paginate(collection)
        Kaminari.paginate_array(collection).page(params[:page]).per(PAGE_SIZE)
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
