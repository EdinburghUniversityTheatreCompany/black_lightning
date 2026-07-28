module Admin
  module Reimbursements
    ##
    # Producer-facing reimbursements portal, part of the members' backend.
    # Access needs the grid permission "Access the Reimbursements portal"
    # (`:access, :reimbursements`) on top of backend access. Data is reached
    # through the Store, never the AR models directly, and every action is
    # scoped to the member's own linked People record.
    class BaseController < AdminController
      # Raised when the expense is the member's own but review has since picked
      # it up, so it's no longer editable (a race against an Edit link on a
      # stale list). Subclasses RecordNotFound so callers that don't
      # distinguish (the receipts turbo actions) still degrade to a 404, while
      # the producer expenses controller can rescue it for a friendly redirect.
      ExpenseNoLongerEditable = Class.new(ActiveRecord::RecordNotFound)

      before_action :authorize_reimbursements!

      # Injection seams for functional tests (this suite has no mocking library).
      #
      # A test must write each seam on ONE class and stick to it, and put the previous value
      # back afterwards. class_attribute's writer defines a singleton reader on whatever
      # receives it, so writing to a SUBCLASS shadows this default permanently for the rest
      # of the process — a later `BaseController.<seam> = fake` is then invisible to that
      # subclass and the real collaborator runs instead. Two suites writing the same seam on
      # different classes therefore pass alone and fail whenever they share a process.
      #
      # Interactive extraction retries less than the background poll job.
      # The store seam takes the financial year the request is scoped to (nil
      # here — see #selected_financial_year). A test fake that ignores scoping
      # is written as `->(**) { fake }`.
      #
      # Named, because a test that has swapped the seam has to put THIS back:
      # restoring it with a hand-written `-> { build_store }` drops the year
      # argument, and class_attribute makes that replacement stick for the rest
      # of the process — so every later year-scoped page in that worker quietly
      # renders every year's budgets at once.
      DEFAULT_STORE_BUILDER =
        ->(financial_year: nil) { ::Reimbursements.build_store(financial_year: financial_year) }

      class_attribute :store_builder, default: DEFAULT_STORE_BUILDER
      class_attribute :extractor_builder, default: -> { ::Reimbursements::Extractor.new(max_attempts: 2) }
      # The Graph-backed email notifier (from the cost centre's send mailbox).
      # Lives here, not just on FinanceController, because a budget owner
      # rejecting a claim (MyBudgetsController) emails the payee the same way
      # the finance Review queue does — see RejectsExpenses.
      class_attribute :notifier_builder,
                      default: ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }

      helper_method :current_person

      private

      def notifier
        @notifier ||= notifier_builder.call(cost_centre: ::Reimbursements::CostCentre.default)
      end

      def authorize_reimbursements!
        authorize! :access, :reimbursements
      end

      def store
        @store ||= store_builder.call(financial_year: selected_financial_year)
      end

      # The producer surfaces are never year-scoped. A submitter files against
      # the active year, which DatabaseStore#active_budgets enforces on its own,
      # and their own past claims must stay visible whatever year finance is
      # looking at. FinanceController overrides this with the ?year= selector.
      def selected_financial_year
        nil
      end

      def extractor
        @extractor ||= extractor_builder.call
      end

      def person_link
        @person_link ||= ::Reimbursements::PersonLink.new(store: store)
      end

      def current_person
        return @current_person if defined?(@current_person)

        @current_person = person_link.person_for(current_user)
      end

      # Submitters may only touch their own expenses, and only while they are
      # a draft or pending (once review picks an expense up it's the finance
      # team's). find_expense! survives a stale cached list, e.g. following
      # an email-in link for an expense created by the poll job.
      def find_own_editable_expense!(record_id)
        expense = find_own_expense!(record_id)
        raise ExpenseNoLongerEditable unless expense.editable?

        expense
      end

      # The submitter's own expense at ANY status — for the read-only show page,
      # so a producer can still view a claim (and its receipts) after it's left
      # the editable window. Ownership is still enforced.
      def find_own_expense!(record_id)
        expense = store.find_expense!(record_id)
        unless expense && current_person && expense.person&.record_id == current_person.record_id
          raise ActiveRecord::RecordNotFound
        end

        expense
      end
    end
  end
end
