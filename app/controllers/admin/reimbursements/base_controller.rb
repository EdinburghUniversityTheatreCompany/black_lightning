module Admin
  module Reimbursements
    ##
    # Producer-facing reimbursements portal, part of the members' backend.
    # Access needs the grid permission "Access the Reimbursements portal"
    # (`:access, :reimbursements`) on top of backend access. Data lives in
    # Airtable (via the cache-fronted Store), not ActiveRecord, and every
    # action is scoped to the member's own linked People record.
    class BaseController < AdminController
      before_action :authorize_reimbursements!

      # Injection seams for functional tests (this suite has no mocking library).
      # Interactive extraction retries less than the background poll job.
      class_attribute :store_builder, default: -> { ::Reimbursements::Store.new }
      class_attribute :extractor_builder, default: -> { ::Reimbursements::Extractor.new(max_attempts: 2) }

      helper_method :current_person

      private

      def authorize_reimbursements!
        authorize! :access, :reimbursements
      end

      def store
        @store ||= store_builder.call
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
        expense = store.find_expense!(record_id)
        unless expense && current_person && expense.person&.record_id == current_person.record_id &&
               expense.editable?
          raise ActiveRecord::RecordNotFound
        end
        expense
      end
    end
  end
end
