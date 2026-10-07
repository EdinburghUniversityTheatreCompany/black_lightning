module Admin
  module Reimbursements
    ##
    # Base for the finance operator surfaces, gated by `:manage, :reimbursements_finance`
    # instead of the producer portal's `:access, :reimbursements`.
    class FinanceController < BaseController
      include ::ErrorReporting

      skip_before_action :authorize_reimbursements!
      before_action :authorize_finance!
      before_action :resolve_financial_year!
      before_action :resolve_cost_centre!

      # Test seam: the modulus checker (vendored Pay.UK rule files in production).
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      # Test seam: the app-only Graph client (SharePoint browse, deleting a stale EUSA draft).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      helper_method :modulus_checker, :selected_financial_year, :selectable_financial_years,
                    :selected_cost_centre, :selectable_cost_centres

      PAGE_SIZE = 50

      private

      attr_reader :selected_financial_year, :selected_cost_centre

      def authorize_finance!
        authorize! :manage, :reimbursements_finance
      end

      # --- Financial-year selector ------------------------------------------
      # ?year=fringe-2027 on any budget screen, defaulting to the active year. Resolved in
      # a before_action so the "no such year" alert is set before anything renders and the
      # store is built with the year asked for.

      def resolve_financial_year!
        requested = params[:year].presence
        @selected_financial_year =
          if requested.nil?
            ::Reimbursements::FinancialYear.current
          else
            ::Reimbursements::FinancialYear.find_by(key: requested) || fall_back_to_active_year(requested)
          end
      end

      # An unknown key alerts and falls back: never quietly show another year's money.
      def fall_back_to_active_year(requested)
        flash.now[:alert] = "There's no financial year called #{requested.inspect}. " \
                            "Showing the active year instead."
        ::Reimbursements::FinancialYear.current
      end

      # Every year, for the selector.
      def selectable_financial_years
        @selectable_financial_years ||= ::Reimbursements::FinancialYear.recent_first.to_a
      end

      # --- Cost-centre selector ---------------------------------------------
      # ?cost_centre=termtime on the finance lists (CostCentre is `param: :key`).
      #
      # No centre selected means EVERY centre. CostCentre.default is `order(:id).first`, so
      # defaulting to it would silently empty the second centre's screens.
      #
      # ?cost_centre_id=<id> is what the import wizards (their select and the preview's
      # hidden field) and the budget form post; the key wins when both are present.

      def resolve_cost_centre!
        requested_key = params[:cost_centre].presence
        requested_id = params[:cost_centre_id].presence
        @selected_cost_centre =
          if requested_key
            find_cost_centre_by_key(requested_key)
          elsif requested_id
            selectable_cost_centres.find { |centre| centre.id.to_s == requested_id.to_s }
          end
      end

      # An unknown key alerts and falls back to every centre, never to another's money.
      def find_cost_centre_by_key(requested)
        centre = selectable_cost_centres.find { |c| c.key == requested }
        return centre if centre

        flash.now[:alert] = "There's no cost centre called #{requested.inspect}. " \
                            "Showing every cost centre instead."
        nil
      end

      # Read off the model, not the store: this runs in the before_action that decides
      # how the store is built.
      def selectable_cost_centres
        @selectable_cost_centres ||= ::Reimbursements::CostCentre.order(:name).to_a
      end

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def graph
        @graph ||= graph_builder.call
      end

      # +store.public_send(finder, id)+, or a 404.
      def find_or_404(finder, id = params[:id])
        store.public_send(finder, id) || raise(ActiveRecord::RecordNotFound)
      end

      def find_expense!
        find_or_404(:find_expense)
      end

      def paginate(collection, per: PAGE_SIZE)
        Kaminari.paginate_array(collection).page(params[:page]).per(per)
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      # The "Download CSV" response behind every finance list. Pass the FULL filtered
      # set: an export is never paged. The exporter owns the columns and filename.
      def send_export(exporter_class, collection)
        exporter = exporter_class.new(store: store, checker: modulus_checker)
        send_data exporter.to_csv(collection), type: "text/csv", filename: exporter.filename
      end

      # A submitted link id (budget_record_id, owner_ids) must resolve first, or the FK
      # raises a 500 instead of a flash naming what to fix.
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
