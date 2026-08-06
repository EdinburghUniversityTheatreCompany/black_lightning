module Climate
  ##
  # The outdoor comparison line, from Open-Meteo's free forecast API.
  #
  # This is the outdoor-weather SEAM: anything that answers #hourly_series with
  # the same row shape can replace it (Met Office DataHub, NOAA METAR at EGPH),
  # which is why the sensor's source column resolves the client rather than the
  # callers naming this class. See Climate::OUTDOOR_SOURCES.
  #
  # Free tier: no API key, 10k calls/day, CC BY 4.0 attribution required,
  # NON-COMMERCIAL use only. Bedlam is a student theatre, so that is fine — but
  # it is a licence condition, not a courtesy, hence ATTRIBUTION below being
  # rendered on the dashboard.
  #
  # The reason this beat the alternatives is +past_days+: every call re-serves
  # the last N days, so the hourly poll upserts a rolling window and any outage
  # gap fills itself on the next successful call. There is no backfill code
  # anywhere in this feature because of that one parameter.
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
        # Ask for our own zone so the timestamps line up with the Govee readings
        # without a conversion step.
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
        # A row missing either driving reading is dropped: a stored row of nils
        # would draw as a gap anyway, but would also block the self-healing
        # re-upsert from ever filling it in.
        next if time.blank? || temperature.nil? || humidity.nil?

        { recorded_at: Time.zone.parse(time),
          temperature_c: temperature.to_f,
          relative_humidity: humidity.to_f,
          dew_point_c: dew_point(dew_points[index], temperature, humidity) }
      end
    end

    # Open-Meteo supplies dew point directly; falling back to our own formula
    # keeps a row usable if it ever stops.
    def dew_point(reported, temperature, humidity)
      return reported.to_f unless reported.nil?

      DewPoint.celsius(temperature_c: temperature, relative_humidity: humidity)
    end
  end
end
