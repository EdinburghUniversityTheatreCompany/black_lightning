module Reimbursements
  ##
  # Central access to reimbursements secrets/config. Each key reads the
  # +REIMBURSEMENTS_*+ environment variable first (Kamal-friendly), then the
  # per-environment Rails credentials under +reimbursements:+.
  module Settings
    KEYS = %i[
      azure_tenant_id azure_client_id azure_client_secret
      airtable_pat gemini_api_key alert_email
    ].freeze

    KEYS.each do |key|
      define_singleton_method(key) { raw_value(key) }
    end

    # A Date or nil (never raises on a malformed value).
    def self.azure_secret_expires_on
      raw = raw_value(:azure_secret_expires_on)
      return raw if raw.is_a?(Date)

      Date.parse(raw.to_s)
    rescue Date::Error
      nil
    end

    def self.mailbox_configured?
      [ azure_tenant_id, azure_client_id, azure_client_secret ].all?(&:present?)
    end

    def self.raw_value(key)
      ENV["REIMBURSEMENTS_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:reimbursements, key).presence
    end
    private_class_method :raw_value
  end
end
