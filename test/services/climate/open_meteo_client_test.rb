require "test_helper"

class Climate::OpenMeteoClientTest < ActiveSupport::TestCase
  def build_client(responses)
    http = FakeHttp.new(responses)
    [ Climate::OpenMeteoClient.new(http: http), http ]
  end

  # Shaped exactly like a real response, verified against the live API for
  # Bedlam's coordinates.
  def series_body(times: [ "2026-08-05T12:00", "2026-08-05T13:00" ],
                  temperatures: [ 17.6, 17.6 ],
                  humidities: [ 68, 71 ],
                  dew_points: [ 11.6, 12.2 ])
    {
      latitude: 55.94137, longitude: -3.174408, elevation: 90.0,
      timezone: "Europe/London",
      hourly_units: { time: "iso8601", temperature_2m: "°C",
                      relative_humidity_2m: "%", dew_point_2m: "°C" },
      hourly: { time: times, temperature_2m: temperatures,
                relative_humidity_2m: humidities, dew_point_2m: dew_points }
    }.to_json
  end

  test "maps the parallel hourly arrays into one row per hour" do
    client, = build_client([ [ 200, series_body ] ])

    rows = client.hourly_series(latitude: 55.9467, longitude: -3.1903)

    assert_equal 2, rows.size
    assert_in_delta 17.6, rows.first[:temperature_c], 0.001
    assert_in_delta 68.0, rows.first[:relative_humidity], 0.001
    assert_in_delta 11.6, rows.first[:dew_point_c], 0.001
  end

  test "parses timestamps in the application zone, not UTC" do
    # It returns naive local wall-clock strings; reading them as UTC would shift
    # every outdoor point an hour through BST.
    client, = build_client([ [ 200, series_body(times: [ "2026-08-05T12:00" ],
                                                temperatures: [ 17.6 ], humidities: [ 68 ],
                                                dew_points: [ 11.6 ]) ] ])

    recorded_at = client.hourly_series(latitude: 55.9467, longitude: -3.1903).first[:recorded_at]

    assert_equal Time.zone.parse("2026-08-05T12:00"), recorded_at
    assert_equal 12, recorded_at.in_time_zone(Time.zone).hour
  end

  test "requests the three variables plus a past window in the app time zone" do
    client, http = build_client([ [ 200, series_body ] ])

    client.hourly_series(latitude: 55.9467, longitude: -3.1903)

    uri = CGI.unescape(http.requests.first.uri)

    assert_includes uri, "latitude=55.9467"
    assert_includes uri, "longitude=-3.1903"
    assert_includes uri, "temperature_2m"
    assert_includes uri, "relative_humidity_2m"
    assert_includes uri, "dew_point_2m"
    assert_includes uri, "timezone=Europe/London"
    assert_includes uri, "past_days=2"
  end

  test "needs no api key" do
    # Nothing to configure, so no environment can be half set up.
    client, http = build_client([ [ 200, series_body ] ])

    client.hourly_series(latitude: 55.9467, longitude: -3.1903)

    assert_empty http.requests.first.headers.keys.grep(/key|auth/i)
  end

  test "past_days is what makes an outage self-heal" do
    # Each poll re-serves the last N days, so a gap fills itself.
    client, http = build_client([ [ 200, series_body ] ])

    client.hourly_series(latitude: 55.9467, longitude: -3.1903, past_days: 7)

    assert_includes CGI.unescape(http.requests.first.uri), "past_days=7"
  end

  test "drops an hour whose temperature is null rather than storing a blank" do
    # The forecast tail can carry nulls; a row of nils is worse than no row.
    client, = build_client([ [ 200, series_body(times: [ "2026-08-05T12:00", "2026-08-05T13:00" ],
                                                temperatures: [ 17.6, nil ],
                                                humidities: [ 68, 71 ],
                                                dew_points: [ 11.6, 12.2 ]) ] ])

    rows = client.hourly_series(latitude: 55.9467, longitude: -3.1903)

    assert_equal 1, rows.size
  end

  test "computes a missing dew point from temperature and humidity" do
    client, = build_client([ [ 200, series_body(times: [ "2026-08-05T12:00" ],
                                                temperatures: [ 20.0 ], humidities: [ 50 ],
                                                dew_points: [ nil ]) ] ])

    rows = client.hourly_series(latitude: 55.9467, longitude: -3.1903)

    assert_in_delta 9.26, rows.first[:dew_point_c], 0.05
  end

  test "returns no rows when the hourly block is absent" do
    client, = build_client([ [ 200, { latitude: 55.9 }.to_json ] ])

    assert_empty client.hourly_series(latitude: 55.9467, longitude: -3.1903)
  end

  test "raises Error on a non-200 carrying the API's reason" do
    body = { error: true, reason: "Value cannot be negative" }.to_json
    client, = build_client([ [ 400, body ] ])

    error = assert_raises(Climate::OpenMeteoClient::Error) do
      client.hourly_series(latitude: 55.9467, longitude: -3.1903)
    end

    assert_match(/cannot be negative/, error.message)
  end

  test "raises Error on an unparseable body" do
    client, = build_client([ [ 200, "<html>502</html>" ] ])

    assert_raises(Climate::OpenMeteoClient::Error) do
      client.hourly_series(latitude: 55.9467, longitude: -3.1903)
    end
  end

  test "lets a transport-level failure propagate" do
    client, = build_client([ Net::ReadTimeout.new ])

    assert_raises(Net::ReadTimeout) do
      client.hourly_series(latitude: 55.9467, longitude: -3.1903)
    end
  end

  test "carries the attribution the licence requires" do
    assert Climate::OpenMeteoClient::ATTRIBUTION.present?
    assert_match(/open-meteo/i, Climate::OpenMeteoClient::ATTRIBUTION_URL)
  end
end
