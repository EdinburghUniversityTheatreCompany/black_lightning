module Climate
  ##
  # Central access to climate-monitor secrets/config. Each key reads the
  # +CLIMATE_*+ environment variable first (Kamal-friendly, and how fnox
  # supplies it in development), then the per-environment Rails credentials
  # under +climate:+.
  #
  # There is deliberately no key for the outdoor source: Open-Meteo's free tier
  # needs none, which is part of why it was chosen.
  module Settings
    KEYS = %i[govee_api_key].freeze

    KEYS.each do |key|
      define_singleton_method(key) { raw_value(key) }
    end

    # The poll job no-ops rather than failing when this is false, so an
    # environment with no Govee key configured is simply quiet.
    def self.govee_configured?
      govee_api_key.present?
    end

    def self.raw_value(key)
      ENV["CLIMATE_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:climate, key).presence
    end
    private_class_method :raw_value
  end
end
