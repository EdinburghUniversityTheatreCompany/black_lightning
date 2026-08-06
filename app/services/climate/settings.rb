module Climate
  ##
  # Config for the climate monitor. Only one thing needs configuring: the shared
  # mailbox Govee's scheduled export lands in. Everything else is a database row.
  #
  # The Graph credential itself is shared and lives in Graph::Settings — the
  # Entra app just needs an ApplicationAccessPolicy covering this mailbox too.
  module Settings
    def self.mailbox
      ENV["CLIMATE_MAILBOX"].presence || Rails.application.credentials.dig(:climate, :mailbox).presence
    end

    # The poll job no-ops rather than failing when this is unset, so an
    # environment without a climate mailbox is simply quiet.
    def self.mailbox_configured?
      mailbox.present? && ::Graph::Settings.configured?
    end
  end
end
