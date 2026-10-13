module Reimbursements
  ##
  # Base for reimbursements jobs: the store_builder seam and +store+.
  class ApplicationJob < ::ApplicationJob
    include ::ErrorReporting

    class_attribute :store_builder, default: -> { Reimbursements.build_store }

    private

    def store
      @store ||= store_builder.call
    end
  end
end
