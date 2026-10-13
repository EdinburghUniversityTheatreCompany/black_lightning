module Graph
  # The Graph app credentials shared by every mailbox integration, climate included. They live
  # under +reimbursements:+ (or +REIMBURSEMENTS_AZURE_*+) because that is where production keeps
  # them: there is one Entra app registration, and Reimbursements::Settings reads the same keys.
  module Settings
    extend ::Settings::Base

    reads_from env: "REIMBURSEMENTS", credentials: :reimbursements

    setting :azure_tenant_id, :azure_client_id, :azure_client_secret

    def self.configured?
      settings_present?
    end

    # Whether replies, moves and mark-reads happen: production, or elsewhere only with the
    # opt-in, since a dev machine holding real credentials would reply to real senders.
    # See Reimbursements::Settings.
    def self.outbound_enabled?
      return true if Rails.env.production?

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"].present?
    end
  end
end
