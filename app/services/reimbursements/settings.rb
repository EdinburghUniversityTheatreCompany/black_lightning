module Reimbursements
  ##
  # Reimbursements secrets: +REIMBURSEMENTS_*+ ENV first, then credentials.
  module Settings
    extend ::Settings::Base

    reads_from env: "REIMBURSEMENTS", credentials: :reimbursements
    setting :azure_tenant_id, :azure_client_id, :azure_client_secret, :alert_email

    # Whether outbound Graph side effects (sending mail, replying to or moving
    # messages, creating EUSA drafts) happen: always in production, elsewhere
    # only with REIMBURSEMENTS_ENABLE_OUTBOUND. Read-only probes are not gated.
    # (Graph::Settings holds the one implementation.)
    def self.outbound_enabled? = ::Graph::Settings.outbound_enabled?

    # A Date or nil (never raises on a malformed value).
    def self.azure_secret_expires_on
      raw = raw_value(:azure_secret_expires_on)
      return raw if raw.is_a?(Date)

      Date.parse(raw.to_s)
    rescue Date::Error
      nil
    end

    # Not every declared key: a mailbox works without alert_email.
    def self.mailbox_configured?
      settings_present?(:azure_tenant_id, :azure_client_id, :azure_client_secret)
    end
  end
end
