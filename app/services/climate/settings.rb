module Climate
  ##
  # Config for the climate monitor: the shared mailbox Govee's scheduled export
  # lands in. The Graph credential is shared (Graph::Settings); the Entra app
  # just needs access to this mailbox too.
  module Settings
    extend ::Settings::Base

    reads_from env: "CLIMATE", credentials: :climate
    setting :mailbox

    # Unset means the poll job no-ops rather than failing.
    def self.mailbox_configured?
      mailbox.present? && ::Graph::Settings.configured?
    end
  end
end
