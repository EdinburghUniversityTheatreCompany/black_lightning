module Reimbursements
  ##
  # Central access to reimbursements secrets/config. Each key reads the
  # +REIMBURSEMENTS_*+ environment variable first (Kamal-friendly), then the
  # per-environment Rails credentials under +reimbursements:+.
  module Settings
    extend ::Settings::Base

    reads_from env: "REIMBURSEMENTS", credentials: :reimbursements
    setting :azure_tenant_id, :azure_client_id, :azure_client_secret, :alert_email

    # Whether reimbursements may perform *outbound* Microsoft Graph side effects
    # — sending mail, replying to / moving mailbox messages, creating EUSA
    # drafts. Enabled only in production, unless explicitly opted in via
    # REIMBURSEMENTS_ENABLE_OUTBOUND (e.g. a staging box wired to a throwaway
    # mailbox, or the test suite which fakes the transport). Read-only Graph
    # probes (the Settings dashboard reachability checks) are NOT gated by this.
    def self.outbound_enabled?
      return true if Rails.env.production?

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"].present?
    end

    # A Date or nil (never raises on a malformed value).
    def self.azure_secret_expires_on
      raw = raw_value(:azure_secret_expires_on)
      return raw if raw.is_a?(Date)

      Date.parse(raw.to_s)
    rescue Date::Error
      nil
    end

    # Deliberately NOT every declared key: alert_email is optional, and a
    # mailbox is usable without it.
    def self.mailbox_configured?
      settings_present?(:azure_tenant_id, :azure_client_id, :azure_client_secret)
    end
  end
end
