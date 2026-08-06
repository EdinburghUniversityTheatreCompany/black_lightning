module Graph
  ##
  # The Microsoft Graph app credentials, shared by every integration that talks
  # to a shared mailbox.
  #
  # Reads +GRAPH_*+ first, then falls back to the +REIMBURSEMENTS_AZURE_*+ names
  # the reimbursements portal has always used. The fallback is deliberate and
  # not temporary: there is one Entra app registration for the organisation, so
  # renaming the variables would have broken every existing fnox and production
  # credential entry for no gain.
  module Settings
    KEYS = %i[azure_tenant_id azure_client_id azure_client_secret].freeze

    KEYS.each do |key|
      define_singleton_method(key) { raw_value(key) }
    end

    def self.configured?
      KEYS.map { |key| public_send(key) }.all?(&:present?)
    end

    # Whether outbound side effects (replying, moving, marking read) actually
    # happen. Production always; elsewhere only with the opt-in, because a dev
    # machine holding real credentials would otherwise reply to real senders and
    # move real mail. See Reimbursements::Settings for the fuller story.
    def self.outbound_enabled?
      return true if Rails.env.production?

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"].present?
    end

    def self.raw_value(key)
      ENV["GRAPH_#{key.to_s.upcase}"].presence ||
        ENV["REIMBURSEMENTS_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:graph, key).presence ||
        Rails.application.credentials.dig(:reimbursements, key).presence
    end
    private_class_method :raw_value
  end
end
