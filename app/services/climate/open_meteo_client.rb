module Climate
  ##
  # The outdoor comparison line, from Open-Meteo's free forecast API.
  #
  # The outdoor-weather SEAM: anything answering #hourly_series with the same row
  # shape can replace it (Met Office DataHub, NOAA METAR at EGPH), which is why
  # sensor.source resolves the client. See Climate::OUTDOOR_SOURCES.
  #
  # Free tier: no key, 10k calls/day, CC BY 4.0 attribution REQUIRED (a licence
  # condition, hence ATTRIBUTION rendered on the dashboard), non-commercial only.
  #
  # What beat the alternatives is +past_days+: every call re-serves the last N
  # days, so the hourly poll upserts a rolling window and an outage gap fills
  # itself. There is no backfill code in this feature because of that parameter.
  class OpenMeteoClient
    BASE_URL = "https://api.open-meteo.com/v1/forecast".freeze
    ATTRIBUTION = "Weather data by Open-Meteo.com".freeze
    ATTRIBUTION_URL = "https://open-meteo.com/".freeze
    LICENCE = "CC BY 4.0".freeze

    HOURLY_VARIABLES = %w[temperature_2m relative_humidity_2m dew_point_2m].freeze
    DEFAULT_PAST_DAYS = 2
    DEFAULT_FORECAST_DAYS = 1

    class Error < StandardError; end

    def initialize(http: nil)
      @http = http || ::HttpTransport
    end

    # -> [{ recorded_at: Time, temperature_c: Float, relative_humidity: Float,
    #       dew_point_c: Float }]
    def hourly_series(latitude:, longitude:, past_days: DEFAULT_PAST_DAYS,
                      forecast_days: DEFAULT_FORECAST_DAYS)
      body = request(latitude: latitude, longitude: longitude,
                     past_days: past_days, forecast_days: forecast_days)
      hourly = body["hourly"]
      return [] if hourly.blank?

      build_rows(hourly)
    end

    private

    def request(latitude:, longitude:, past_days:, forecast_days:)
      uri = URI.parse(BASE_URL)
      uri.query = URI.encode_www_form(
        latitude: latitude, longitude: longitude,
        hourly: HOURLY_VARIABLES.join(","),
        past_days: past_days, forecast_days: forecast_days,
        # Our own zone, so timestamps line up with the Govee readings.
        timezone: Time.zone.tzinfo.name
      )

      status, body, = @http.call(:get, uri, {}, nil)
      parsed = parse(body, status)
      unless status == 200
        raise Error, "Open-Meteo request failed (HTTP #{status}): " \
                     "#{parsed['reason'].presence || body.to_s.truncate(200)}"
      end

      parsed
    end

    def parse(body, status)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "Open-Meteo returned an unreadable body (HTTP #{status}): #{body.to_s.truncate(200)}"
    end

    def build_rows(hourly)
      times = Array(hourly["time"])
      temperatures = Array(hourly["temperature_2m"])
      humidities = Array(hourly["relative_humidity_2m"])
      dew_points = Array(hourly["dew_point_2m"])

      times.each_with_index.filter_map do |time, index|
        temperature = temperatures[index]
        humidity = humidities[index]
        # A stored row of nils would draw as a gap anyway, and would block the
        # self-healing re-upsert from ever filling it in.
        next if time.blank? || temperature.nil? || humidity.nil?

        { recorded_at: Time.zone.parse(time),
          temperature_c: temperature.to_f,
          relative_humidity: humidity.to_f,
          dew_point_c: dew_point(dew_points[index], temperature, humidity) }
      end
    end

    # Supplied directly; the fallback keeps a row usable if that ever stops.
    def dew_point(reported, temperature, humidity)
      return reported.to_f unless reported.nil?

      DewPoint.celsius(temperature_c: temperature, relative_humidity: humidity)
    end
  end
end
