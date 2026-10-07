module Admin
  module Reimbursements
    ##
    # Base for the reimbursements portal: the `:access, :reimbursements` gate plus
    # the store and notifier seams. Data goes through the store, never the AR models.
    class BaseController < AdminController
      # The expense is the member's own but review has since picked it up. Subclasses
      # RecordNotFound so the receipts turbo actions still 404, while the producer
      # expenses controller rescues it for a friendly redirect.
      ExpenseNoLongerEditable = Class.new(ActiveRecord::RecordNotFound)

      before_action :authorize_reimbursements!

      # Injection seams for functional tests (no mocking library).
      #
      # Write each seam on ONE class and put the previous value back afterwards.
      # class_attribute's writer defines a singleton reader on whatever receives it, so
      # writing to a SUBCLASS shadows this default for the rest of the process: a later
      # `BaseController.<seam> = fake` is invisible to that subclass. Two suites writing
      # one seam on different classes pass alone and fail together.
      #
      # The store seam takes the request's scope (financial_year, cost_centre; nil here).
      # A fake that ignores scoping is `->(**) { fake }`. Restore THIS constant, never a
      # hand-written `-> { build_store }`: it drops both arguments, and the replacement
      # sticks, so every later scoped page renders every year's and centre's budgets at once.
      DEFAULT_STORE_BUILDER = ::Reimbursements.method(:build_store)

      class_attribute :store_builder, default: DEFAULT_STORE_BUILDER
      # Here, not on FinanceController, because a budget owner rejecting a claim
      # (MyBudgetsController) emails the payee the same way (see RejectsExpenses).
      class_attribute :notifier_builder,
                      default: ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }

      helper_method :current_person

      private

      # The notifier for the centre that owns the claim: its send mailbox is where a
      # rejection comes FROM. Per centre, not one on CostCentre.default, which sent every
      # claim's mail from centre #1. An unplaced claim falls back to the default centre:
      # a wrong mailbox is visible and answerable, raising would block the rejection.
      def notifier_for(cost_centre)
        centre = cost_centre || ::Reimbursements::CostCentre.default
        @notifiers ||= {}
        @notifiers[centre&.id] ||= notifier_builder.call(cost_centre: centre)
      end

      def authorize_reimbursements!
        authorize! :access, :reimbursements
      end

      def store
        @store ||= store_builder.call(financial_year: selected_financial_year,
                                      cost_centre: selected_cost_centre)
      end

      # Producer surfaces are never year-scoped: a submitter files against the active
      # year (DatabaseStore#active_budgets enforces it) and their past claims stay
      # visible. FinanceController overrides this with the ?year= selector.
      def selected_financial_year
        nil
      end

      # Nor cost-centre scoped: a producer's claims span every centre they filed in, and
      # the budget picker is centre-blind on purpose. FinanceController overrides this.
      def selected_cost_centre
        nil
      end

      def person_link
        @person_link ||= ::Reimbursements::PersonLink.new(store: store)
      end

      def current_person
        return @current_person if defined?(@current_person)

        @current_person = person_link.person_for(current_user)
      end

      # A submitter may edit only their own Draft/Pending claims.
      def find_own_editable_expense!(record_id)
        expense = find_own_expense!(record_id)
        raise ExpenseNoLongerEditable unless expense.editable?

        expense
      end

      # The submitter's own expense at any status, for the read-only show page.
      def find_own_expense!(record_id)
        expense = store.find_expense!(record_id)
        raise ActiveRecord::RecordNotFound unless expense && own_expense?(expense)

        expense
      end

      def own_expense?(expense)
        current_person.present? && expense.person&.record_id == current_person.record_id
      end
    end
  end
end
