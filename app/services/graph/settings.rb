module Graph
  # The Graph app credentials shared by every mailbox integration. Reads +GRAPH_*+ first, then
  # falls back to +REIMBURSEMENTS_AZURE_*+. The fallback is permanent: there is one Entra app
  # registration, and renaming the variables would break every existing ENV and credential entry.
  module Settings
    extend ::Settings::Base

    reads_from env: "GRAPH", credentials: :graph
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
