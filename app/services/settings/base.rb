# frozen_string_literal: true

module Settings
  # The ENV-then-credentials lookup shared by every integration's Settings module: +PREFIX_KEY+
  # from the environment first, then the per-environment credentials under a namespace.
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
  # The leading +::+ is required: inside +Pretix::Settings+, +Settings+ resolves to the enclosing
  # module first, so a bare +Settings::Base+ looks for +Pretix::Settings::Base+.
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
      @settings_source = Source.new(env: env, credentials: credentials)
    end

    # Declare one or more keys, each getting a reader of the same name.
    def setting(*names)
      names.each do |name|
        settings_keys << name
        define_singleton_method(name) { raw_value(name) }
      end
    end

    # Declaration order, so a +configured?+ can ask for "all of them" without repeating the list.
    def settings_keys
      @settings_keys ||= []
    end

    def settings_present?(*names)
      names = settings_keys if names.empty?
      names.map { |name| public_send(name) }.all?(&:present?)
    end

    private

    # Also used by hand-written readers that post-process the raw value
    # (Reimbursements::Settings#azure_secret_expires_on).
    def raw_value(key)
      @settings_source.env_value(key) || @settings_source.credentials_value(key)
    end
  end
end
