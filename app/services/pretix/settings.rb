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

    # "EUTC Member". max_usages is null (unlimited uses) and allow_parallel_usage
    # is false, so one membership buys any number of member tickets but only one
    # seat per performance.
    MEMBERSHIP_TYPE_ID = 225

    def self.api_token
      raw_value(:api_token)
    end

    def self.configured?
      api_token.present?
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

    def self.raw_value(key)
      ENV["PRETIX_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:pretix, key).presence
    end
    private_class_method :raw_value
  end
end
