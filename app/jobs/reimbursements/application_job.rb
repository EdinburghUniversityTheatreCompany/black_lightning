module Reimbursements
  ##
  # Shared base for every reimbursements job. +store_builder+/+store+ was
  # hand-copied identically across MailboxPollJob, NightlyBatchJob,
  # BuildBatchJob and AiCheckJob; hoisted here so there's one place to change
  # it. CredentialsCheckJob doesn't touch the store, but inheriting the unused
  # seam costs nothing.
  class ApplicationJob < ::ApplicationJob
    include ErrorReporting

    class_attribute :store_builder, default: -> { Store.new }

    private

    def store
      @store ||= store_builder.call
    end
  end
end
