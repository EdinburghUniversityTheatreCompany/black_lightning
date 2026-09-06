# frozen_string_literal: true

module Pretix
  ##
  # Config and secrets for the pretix REST API. Reads +PRETIX_*+ from the
  # environment first (Kamal-friendly, fnox in development), then per-environment
  # Rails credentials under +pretix:+, following Reimbursements::Settings.
  module Settings
    # The shop runs on a custom domain, but the API is only served from pretix.eu.
    API_BASE = "https://pretix.eu/api/v1/"

    ORGANIZER = "eutc"

    # The shop's own domain, which is also where pretix sends people back after
    # SSO. Taken from PretixHelper so the widget and the sync cannot disagree
    # about which host is the shop.
    SHOP_HOST = URI(PretixHelper::SHOP_URL).host.freeze

    # "EUTC Member". max_usages is null (unlimited uses) and allow_parallel_usage
    # is false, so one membership buys any number of member tickets but only one
    # seat per performance.
    MEMBERSHIP_TYPE_ID = 225

    extend ::Settings::Base

    reads_from env: "PRETIX", credentials: :pretix
    setting :api_token

    def self.configured?
      settings_present?
    end

    # Whether the sync may WRITE to pretix. Reads stay live everywhere so the
    # spike and any dashboard still work, but a dev machine holding a token must
    # never create or expire memberships in the live shop — there is one pretix
    # organizer and no staging copy of it, so a stray reconcile would revoke
    # member pricing for real people.
    def self.writes_enabled?
      return true if Rails.env.production?

      ENV["PRETIX_ENABLE_WRITES"].present?
    end
  end
end
