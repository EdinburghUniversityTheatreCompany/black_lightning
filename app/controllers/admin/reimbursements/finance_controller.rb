module Admin
  module Reimbursements
    ##
    # Base for the finance-team operator surfaces (People, Review, Batches,
    # Reconcile, Settings). These are gated by the finance grid permission
    # (`:manage, :reimbursements_finance`) instead of the producer portal's
    # `:access, :reimbursements`, so a plain submitter can't reach them.
    class FinanceController < BaseController
      include ::ErrorReporting

      skip_before_action :authorize_reimbursements!
      before_action :authorize_finance!
      before_action :resolve_financial_year!

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

      helper_method :modulus_checker, :selected_financial_year, :selectable_financial_years

      # A page of records for an index view. One shared page size (50) across
      # every finance list, so a future change to it is a single edit.
      PAGE_SIZE = 50

      private

      def authorize_finance!
        authorize! :manage, :reimbursements_finance
      end

      # --- Financial-year selector ------------------------------------------
      # URL-as-state: ?year=fringe-2027 on any budget screen, defaulting to the
      # active year. Resolved in a before_action rather than lazily, so the
      # "no such year" alert is set before anything renders — and so the store
      # is built with the year the operator actually asked for.

      def resolve_financial_year!
        requested = params[:year].presence
        @selected_financial_year =
          if requested.nil?
            ::Reimbursements::FinancialYear.current
          else
            ::Reimbursements::FinancialYear.find_by(key: requested) || fall_back_to_active_year(requested)
          end
      end

      # A year key that matches nothing must never quietly show a DIFFERENT
      # year's money as though it were the requested one — say so, then fall
      # back to the active year.
      def fall_back_to_active_year(requested)
        flash.now[:alert] = "There's no financial year called #{requested.inspect}. " \
                            "Showing the active year instead."
        ::Reimbursements::FinancialYear.current
      end

      def selected_financial_year
        @selected_financial_year
      end

      # Every year, for the selector. Empty until the first year is created,
      # which is the state a pre-financial-year database is in.
      def selectable_financial_years
        @selectable_financial_years ||= ::Reimbursements::FinancialYear.recent_first.to_a
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

      # The one "Download CSV" response behind every finance list's
      # +format.csv+. Callers pass the FULL filtered set — the on-screen
      # filters carry through the query string, but pagination is display-only,
      # so an export is never paged. The exporter owns the columns (and the
      # filename), so the CSV and the combined workbook's matching sheet can
      # never drift apart.
      def send_export(exporter_class, collection)
        exporter = exporter_class.new(store: store, checker: modulus_checker)
        send_data exporter.to_csv(collection), type: "text/csv", filename: exporter.filename
      end

      # A submitted link id (budget_record_id, owner_ids) must resolve to a real
      # record before the link is written: the FK would otherwise raise, giving
      # the operator a 500 instead of a flash naming what to fix.
      def budget_record_id_error(record_id)
        return nil if record_id.blank?
        return nil if store.find_budget(record_id)

        "That budget no longer exists. Please pick another."
      end

      def owner_ids_error(record_ids)
        unknown = Array(record_ids).reject(&:blank?).reject { |id| store.find_person(id) }
        return nil if unknown.empty?

        "One or more selected owners no longer exist. Please update the list."
      end
    end
  end
end
