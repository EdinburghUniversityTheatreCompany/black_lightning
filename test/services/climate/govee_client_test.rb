require "test_helper"

class Climate::GoveeClientTest < ActiveSupport::TestCase
  # Stands in for Climate::Settings without touching ENV or credentials.
  FakeSettings = Struct.new(:govee_api_key, keyword_init: true) do
    def govee_configured? = govee_api_key.present?
  end

  def build_client(responses, api_key: "test-key")
    http = FakeHttp.new(responses)
    [ Climate::GoveeClient.new(settings: FakeSettings.new(govee_api_key: api_key), http: http), http ]
  end

  # A real /user/devices body, trimmed to the fields we read.
  def devices_body(extra_devices: [])
    {
      code: 200, message: "success",
      data: [
        {
          sku: "H5179", device: "AA:BB:CC:DD:EE:FF", deviceName: "Crypt north",
          type: "devices.types.thermometer",
          capabilities: [
            { type: "devices.capabilities.property", instance: "sensorTemperature" },
            { type: "devices.capabilities.property", instance: "sensorHumidity" }
          ]
        },
        *extra_devices
      ]
    }.to_json
  end

  def state_body(temperature: 53.6, humidity: 78, online: true)
    {
      requestId: "uuid", code: 200, msg: "success",
      payload: {
        sku: "H5179", device: "AA:BB:CC:DD:EE:FF",
        capabilities: [
          { type: "devices.capabilities.online", instance: "online", state: { value: online } },
          { type: "devices.capabilities.property", instance: "sensorTemperature",
            state: { value: temperature } },
          { type: "devices.capabilities.property", instance: "sensorHumidity",
            state: { value: humidity } }
        ]
      }
    }.to_json
  end

  # --- devices ---------------------------------------------------------------

  test "lists thermometers with their device id, sku and name" do
    client, = build_client([ [ 200, devices_body ] ])

    devices = client.devices

    assert_equal 1, devices.size
    assert_equal "AA:BB:CC:DD:EE:FF", devices.first.external_id
    assert_equal "H5179", devices.first.sku
    assert_equal "Crypt north", devices.first.name
  end

  test "ignores devices that are not thermometers" do
    # The same Govee account drives the theatre's lights; those must never turn
    # up as sensors to be polled.
    light = { sku: "H6199", device: "11:22:33:44:55:66", deviceName: "Foyer strip",
              type: "devices.types.light", capabilities: [] }
    client, = build_client([ [ 200, devices_body(extra_devices: [ light ]) ] ])

    assert_equal [ "AA:BB:CC:DD:EE:FF" ], client.devices.map(&:external_id)
  end

  test "sends the api key header" do
    client, http = build_client([ [ 200, devices_body ] ])

    client.devices

    assert_equal "test-key", http.requests.first.headers["Govee-API-Key"]
  end

  test "asks Govee for the device list over GET" do
    client, http = build_client([ [ 200, devices_body ] ])

    client.devices

    assert_equal :get, http.requests.first.method
    assert_includes http.requests.first.uri, "/router/api/v1/user/devices"
  end

  test "raises rather than calling out when no api key is configured" do
    client, http = build_client([], api_key: nil)

    assert_raises(Climate::GoveeClient::ConfigurationError) { client.devices }
    assert_empty http.requests
  end

  # --- state -----------------------------------------------------------------

  test "reads temperature and humidity out of the capability list" do
    client, = build_client([ [ 200, state_body(temperature: 53.6, humidity: 78) ] ])

    state = client.state(sku: "H5179", external_id: "AA:BB:CC:DD:EE:FF")

    assert_in_delta 53.6, state.raw_temperature, 0.001
    assert_in_delta 78.0, state.relative_humidity, 0.001
    assert_predicate state, :online
  end

  test "posts the sku, device and a request id" do
    client, http = build_client([ [ 200, state_body ] ])

    client.state(sku: "H5179", external_id: "AA:BB:CC:DD:EE:FF")

    request = http.requests.first
    body = JSON.parse(request.body)

    assert_equal :post, request.method
    assert_includes request.uri, "/router/api/v1/device/state"
    assert_equal "H5179", body.dig("payload", "sku")
    assert_equal "AA:BB:CC:DD:EE:FF", body.dig("payload", "device")
    assert body["requestId"].present?
  end

  test "reports a device Govee says is offline" do
    # The batteries-dead case: Govee keeps serving the last known value forever,
    # so this flag is the only thing that stops us writing a flat fake line.
    client, = build_client([ [ 200, state_body(online: false) ] ])

    assert_not client.state(sku: "H5179", external_id: "AA:BB:CC:DD:EE:FF").online
  end

  test "accepts a humidity reported as a nested currentHumidity value" do
    # Some Govee firmware nests it; the flat form is what H5179 sends today.
    body = {
      code: 200,
      payload: { capabilities: [
        { instance: "sensorTemperature", state: { value: 50.0 } },
        { instance: "sensorHumidity", state: { value: { currentHumidity: 81 } } }
      ] }
    }.to_json
    client, = build_client([ [ 200, body ] ])

    assert_in_delta 81.0, client.state(sku: "H5179", external_id: "x").relative_humidity, 0.001
  end

  test "returns nil readings when a capability is absent rather than inventing zero" do
    body = { code: 200, payload: { capabilities: [] } }.to_json
    client, = build_client([ [ 200, body ] ])

    state = client.state(sku: "H5179", external_id: "x")

    assert_nil state.raw_temperature
    assert_nil state.relative_humidity
  end

  # --- errors ----------------------------------------------------------------

  test "raises AuthError on a 401 so the caller can stop the whole cycle" do
    client, = build_client([ [ 401, { message: "invalid key" }.to_json ] ])

    assert_raises(Climate::GoveeClient::AuthError) { client.devices }
  end

  test "raises AuthError on a 403" do
    client, = build_client([ [ 403, "" ] ])

    assert_raises(Climate::GoveeClient::AuthError) { client.devices }
  end

  test "raises RateLimitedError on a 429" do
    client, = build_client([ [ 429, { message: "too many requests" }.to_json ] ])

    assert_raises(Climate::GoveeClient::RateLimitedError) { client.devices }
  end

  test "raises Error carrying Govee's own message on a 500" do
    client, = build_client([ [ 500, { message: "internal blew up" }.to_json ] ])

    error = assert_raises(Climate::GoveeClient::Error) { client.devices }

    assert_match(/internal blew up/, error.message)
  end

  test "treats a non-200 code in a 200 body as an error" do
    # Govee sometimes answers HTTP 200 with a failure code in the payload.
    client, = build_client([ [ 200, { code: 400, message: "invalid device" }.to_json ] ])

    error = assert_raises(Climate::GoveeClient::Error) { client.devices }

    assert_match(/invalid device/, error.message)
  end

  test "raises Error rather than exploding on an unparseable body" do
    client, = build_client([ [ 200, "<html>gateway timeout</html>" ] ])

    assert_raises(Climate::GoveeClient::Error) { client.devices }
  end

  test "lets a transport-level failure propagate" do
    client, = build_client([ Net::OpenTimeout.new("timed out") ])

    assert_raises(Net::OpenTimeout) { client.devices }
  end

  # --- rate limit ------------------------------------------------------------

  test "reads the remaining daily budget from the response headers" do
    # The 10,000/day cap is per Govee ACCOUNT, not per key, so if this key is
    # ever shared with another integration we need to see it coming.
    client, = build_client([ [ 200, devices_body, { "x-ratelimit-remaining" => "8123" } ] ])

    client.devices

    assert_equal 8123, client.rate_limit_remaining
  end

  test "leaves the remaining budget nil when Govee sends no such header" do
    client, = build_client([ [ 200, devices_body ] ])

    client.devices

    assert_nil client.rate_limit_remaining
  end
end
