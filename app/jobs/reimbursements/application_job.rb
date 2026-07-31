module Reimbursements
  ##
  # Shared base for every reimbursements job: the one definition of
  # +store_builder+/+store+, which MailboxPollJob, NightlyBatchJob and
  # BuildBatchJob all need. CredentialsCheckJob doesn't touch the store, but
  # inheriting the unused seam costs nothing.
  class ApplicationJob < ::ApplicationJob
    include ErrorReporting

    class_attribute :store_builder, default: -> { Reimbursements.build_store }

    private

    def store
      @store ||= store_builder.call
    end
  end
end
