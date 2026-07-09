module Reimbursements
  ##
  # Central access to reimbursements secrets/config. Each key reads the
  # +REIMBURSEMENTS_*+ environment variable first (Kamal-friendly), then the
  # per-environment Rails credentials under +reimbursements:+.
  module Settings
    KEYS = %i[
      azure_tenant_id azure_client_id azure_client_secret
      azure_secret_expires_on airtable_pat gemini_api_key alert_email
    ].freeze

    KEYS.each do |key|
      define_singleton_method(key) do
        ENV["REIMBURSEMENTS_#{key.to_s.upcase}"].presence ||
          Rails.application.credentials.dig(:reimbursements, key).presence
      end
    end

    # Overrides the generated reader: returns a Date or nil (never raises).
    def self.azure_secret_expires_on
      raw = ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"].presence ||
            Rails.application.credentials.dig(:reimbursements, :azure_secret_expires_on).presence
      return raw if raw.is_a?(Date)

      Date.parse(raw.to_s)
    rescue Date::Error
      nil
    end

    def self.mailbox_configured?
      [ azure_tenant_id, azure_client_id, azure_client_secret ].all?(&:present?)
    end
  end
end
