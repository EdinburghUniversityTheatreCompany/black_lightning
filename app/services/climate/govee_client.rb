module Climate
  ##
  # The Govee Developer API v2 (https://openapi.api.govee.com), used to list the
  # thermo-hygrometers on the account and read their current state.
  #
  # Two things about this API shape the whole feature:
  #
  # 1. There is NO history endpoint. It serves "now" and nothing else, which is
  #    why climate_readings has to be accumulated by a poll job.
  # 2. The unit of +sensorTemperature+ is undocumented and is widely reported as
  #    Fahrenheit even where the app displays Celsius. This client therefore
  #    returns the number VERBATIM as +raw_temperature+ and converts nothing —
  #    the conversion belongs to ReadingIngest, which knows the operator-verified
  #    unit for that particular sensor.
  class GoveeClient
    BASE_URL = "https://openapi.api.govee.com".freeze
    DEVICES_PATH = "/router/api/v1/user/devices".freeze
    STATE_PATH = "/router/api/v1/device/state".freeze
    THERMOMETER_TYPE = "devices.types.thermometer".freeze

    TEMPERATURE_INSTANCE = "sensorTemperature".freeze
    HUMIDITY_INSTANCE = "sensorHumidity".freeze
    ONLINE_INSTANCE = "online".freeze

    # Below this many requests left on the daily budget, the poll job warns.
    LOW_RATE_LIMIT = 1_000

    class Error < StandardError; end
    # No API key at all — a configuration problem, not a service failure.
    class ConfigurationError < Error; end
    # 401/403: the key is wrong or revoked. Shared across every sensor, so the
    # caller should abandon the whole cycle rather than retry per device.
    class AuthError < Error; end
    # 429, or the daily cap exhausted.
    class RateLimitedError < Error; end

    Device = Struct.new(:external_id, :sku, :name, keyword_init: true)
    State = Struct.new(:raw_temperature, :relative_humidity, :online, :fetched_at,
                       keyword_init: true)

    # Requests left on the account's daily budget as of the last response, or
    # nil if Govee sent no header.
    attr_reader :rate_limit_remaining

    def initialize(settings: Climate::Settings, http: nil, clock: nil)
      @settings = settings
      @http = http || ::HttpTransport
      @clock = clock || -> { Time.current }
      @rate_limit_remaining = nil
    end

    # Every thermometer on the account. Lights, plugs and humidifiers on the
    # same account are filtered out here so they can never be polled as sensors.
    def devices
      body = request(:get, DEVICES_PATH)

      Array(body["data"])
        .select { |device| device["type"] == THERMOMETER_TYPE }
        .map do |device|
          Device.new(external_id: device["device"], sku: device["sku"],
                     name: device["deviceName"].presence || device["device"])
        end
    end

    def state(sku:, external_id:)
      body = request(:post, STATE_PATH,
                     payload: { requestId: SecureRandom.uuid,
                                payload: { sku: sku, device: external_id } })
      capabilities = Array(body.dig("payload", "capabilities"))

      State.new(
        raw_temperature: numeric(capability_value(capabilities, TEMPERATURE_INSTANCE)),
        relative_humidity: numeric(capability_value(capabilities, HUMIDITY_INSTANCE)),
        # Absent means present-and-reporting: only an explicit false is offline.
        online: capability_value(capabilities, ONLINE_INSTANCE) != false,
        fetched_at: @clock.call
      )
    end

    def rate_limit_low? = rate_limit_remaining.present? && rate_limit_remaining < LOW_RATE_LIMIT

    private

    def api_key
      @settings.govee_api_key.presence ||
        raise(ConfigurationError, "No Govee API key configured (CLIMATE_GOVEE_API_KEY)")
    end

    def request(method, path, payload: nil)
      uri = URI.join(BASE_URL, path)
      headers = { "Govee-API-Key" => api_key, "Content-Type" => "application/json" }

      status, body, response_headers = @http.call(method, uri, headers, payload&.to_json)
      record_rate_limit(response_headers)

      raise AuthError, "Govee rejected the API key (HTTP #{status})" if [ 401, 403 ].include?(status)
      raise RateLimitedError, "Govee rate limit reached (HTTP #{status})" if status == 429

      parsed = parse(body, status)
      raise Error, "Govee request failed (HTTP #{status}): #{message_from(parsed, body)}" unless status == 200

      # Govee also signals failure with a non-200 "code" inside a 200 response.
      code = parsed["code"]
      raise Error, "Govee request failed (code #{code}): #{message_from(parsed, body)}" if code.present? && code.to_i != 200

      parsed
    end

    def parse(body, status)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "Govee returned an unreadable body (HTTP #{status}): #{body.to_s.truncate(200)}"
    end

    def message_from(parsed, body)
      parsed["message"].presence || parsed["msg"].presence || body.to_s.truncate(200)
    end

    def capability_value(capabilities, instance)
      capability = capabilities.find { |item| item["instance"] == instance }
      return nil if capability.nil?

      capability.dig("state", "value")
    end

    # Readings arrive as a bare number, but some firmware nests humidity under
    # currentHumidity. Anything else is treated as absent rather than coerced —
    # a wrong number here becomes stored history.
    def numeric(value)
      case value
      when Numeric then value.to_f
      when Hash then value["currentHumidity"]&.to_f
      end
    end

    def record_rate_limit(response_headers)
      remaining = response_headers.to_h.transform_keys(&:downcase)["x-ratelimit-remaining"]
      @rate_limit_remaining = remaining.presence&.to_i
    end
  end
end
