# frozen_string_literal: true

module Pretix
  # Config and secrets for the pretix REST API: +PRETIX_*+ from the environment,
  # then Rails credentials under +pretix:+, following Reimbursements::Settings.
  module Settings
    # The shop runs on a custom domain, but the API is only served from pretix.eu.
    API_BASE = "https://pretix.eu/api/v1/"

    ORGANIZER = "eutc"

    # The shop's own domain, also where pretix sends people back after SSO. Taken
    # from PretixHelper so the widget and the sync cannot disagree on the host.
    SHOP_HOST = URI(PretixHelper::SHOP_URL).host.freeze

    # "EUTC Member": unlimited uses, no parallel usage, so any number of member
    # tickets but one seat per performance.
    MEMBERSHIP_TYPE_ID = 225

    extend ::Settings::Base

    reads_from env: "PRETIX", credentials: :pretix
    setting :api_token

    def self.configured?
      settings_present?
    end

    # Whether the sync may WRITE to pretix. A dev machine holding a token must never
    # create or expire memberships: there is one organizer and no staging copy, so a
    # stray reconcile would revoke member pricing for real people.
    def self.writes_enabled?
      return true if Rails.env.production?

      ENV["PRETIX_ENABLE_WRITES"].present?
    end
  end
end
