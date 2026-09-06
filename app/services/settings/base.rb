# frozen_string_literal: true

module Settings
  ##
  # The ENV-then-credentials lookup every integration's Settings module does:
  # read +PREFIX_KEY+ from the environment first (Kamal-friendly in production,
  # fnox in development), then the per-environment Rails credentials under a
  # namespace. Four modules had grown their own copy of it.
  #
  #   module Pretix
  #     module Settings
  #       extend ::Settings::Base            # NB the leading "::"
  #
  #       reads_from env: "PRETIX", credentials: :pretix
  #       setting :api_token
  #     end
  #   end
  #
  # The leading +::+ is required, not stylistic: from inside +Pretix::Settings+
  # the constant +Settings+ resolves to the enclosing +Pretix::Settings+ first,
  # so a bare +Settings::Base+ looks for +Pretix::Settings::Base+.
  #
  # +reads_from+ may be called more than once and the sources are tried in the
  # order declared, which is what lets Graph::Settings fall back to the
  # +REIMBURSEMENTS_AZURE_*+ names the portal has always used.
  module Base
    # A place a value may be read from: an ENV prefix and a credentials key.
    Source = Struct.new(:env, :credentials, keyword_init: true) do
      def env_value(key)
        ENV["#{env}_#{key.to_s.upcase}"].presence
      end

      def credentials_value(key)
        Rails.application.credentials.dig(credentials, key).presence
      end
    end

    def reads_from(env:, credentials:)
      settings_sources << Source.new(env: env, credentials: credentials)
    end

    # Declare one or more keys, each getting a reader of the same name.
    def setting(*names)
      names.each do |name|
        settings_keys << name
        define_singleton_method(name) { raw_value(name) }
      end
    end

    def settings_sources
      @settings_sources ||= []
    end

    # The declared keys, in declaration order -- so a `configured?` can ask for
    # "all of them" without repeating the list.
    def settings_keys
      @settings_keys ||= []
    end

    def settings_present?(*names)
      names = settings_keys if names.empty?
      names.map { |name| public_send(name) }.all?(&:present?)
    end

    private

    # Every ENV source is tried before any credentials source, NOT source by
    # source: the environment is how a deployment overrides what is baked into
    # the credentials, so a fallback prefix must still beat the primary
    # namespace's committed value. Graph::Settings is the case that has two of
    # each, and this preserves the order it was written with.
    #
    # Also used directly by hand-written readers that post-process the raw value
    # (Reimbursements::Settings#azure_secret_expires_on).
    def raw_value(key)
      settings_sources.filter_map { |source| source.env_value(key) }.first ||
        settings_sources.filter_map { |source| source.credentials_value(key) }.first
    end
  end
end
