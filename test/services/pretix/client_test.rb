require "test_helper"

class Pretix::ClientTest < ActiveSupport::TestCase
  TOKEN = "s3cr3t-pretix-token".freeze

  # Stands in for Pretix::Settings so the writes gate is decided per client
  # instance. The real one reads ENV outside production, and this suite
  # parallelises — a test that toggled ENV would be reaching for process-global
  # state a sibling test in the same worker also reads.
  FakeSettings = Struct.new(:writes_enabled) do
    def writes_enabled?
      writes_enabled
    end
  end

  # --- rate limiting ---------------------------------------------------------
  #
  # pretix Hosted allows 360 requests/minute per organizer and answers a 429 with
  # Retry-After. Their docs say a client that keeps bursting after one may have
  # its API access disabled, so honouring this is a requirement. It only shows up
  # in production: from a developer machine the round trip to pretix.eu is slow
  # enough to stay under the limit by accident.

  test "a throttled request is retried after the Retry-After the server asked for" do
    client, waits, http = recording_client([
      [ 429, { detail: "Request was throttled." }.to_json, { "retry-after" => "17" } ],
      empty_page
    ])

    assert_empty client.customers
    assert_equal 2, http.requests.size, "the request must actually be retried"
    assert_includes waits, 18, "17 from the header, plus a second of slack"
  end

  test "a 429 with no Retry-After still waits rather than hammering" do
    client, waits, = recording_client([ [ 429, "no body at all" ], empty_page ])

    assert_empty client.customers
    assert_includes waits, Pretix::Client::DEFAULT_RETRY_AFTER
  end

  test "the wait falls back to the body when the header is missing" do
    throttled = { detail: "Request was throttled. Expected available in 42 seconds." }.to_json
    client, waits, = recording_client([ [ 429, throttled ], empty_page ])

    client.customers

    assert_includes waits, 43
  end

  test "an unrelenting throttle eventually raises instead of retrying forever" do
    client, = recording_client(Array.new(Pretix::Client::MAX_THROTTLE_RETRIES + 1) { [ 429, "throttled" ] })

    assert_raises(Pretix::Client::Error) { client.customers }
  end

  test "successive requests are paced apart, so a reconcile cannot burst" do
    client, waits, = recording_client(Array.new(3) { empty_page })

    3.times { client.customers }

    assert_equal 2, waits.size, "the first request waits for nothing; each later one is paced"
    waits.each { |wait| assert_operator wait, :<=, Pretix::Client::MIN_REQUEST_INTERVAL }
  end

  # Returns the client, the seconds it was asked to sleep, and the fake transport.
  def recording_client(responses)
    waits = []
    http = FakeHttp.new(responses)
    client = Pretix::Client.new(token: TOKEN, http: http, settings: FakeSettings.new(false),
                                sleeper: ->(seconds) { waits << seconds })
    [ client, waits, http ]
  end

  def empty_page = [ 200, { "count" => 0, "next" => nil, "results" => [] }.to_json ]

  def build_client(responses, organizer: "eutc", token: TOKEN, writes: false)
    http = FakeHttp.new(responses)
    # No-op sleeper: the pacing and throttle-retry waits are real seconds, and
    # this suite must not spend them.
    client = Pretix::Client.new(organizer: organizer, token: token, http: http,
                                settings: FakeSettings.new(writes), sleeper: ->(_seconds) { })
    [ client, http ]
  end

  def page(results, next_url: nil)
    [ 200, { count: results.size, next: next_url, previous: nil, results: results }.to_json ]
  end

  def customer(identifier: "MG3KL", email: "alice@example.com")
    { identifier: identifier, email: email, external_identifier: email, name: "Alice" }
  end

  def membership(id: 1, customer: "MG3KL")
    { id: id, customer: customer, membership_type: 225,
      date_start: "2026-08-26T00:00:00+01:00", date_end: "2027-09-21T23:59:59+01:00" }
  end

  test "every argument is defaulted, so the sync can build a bare client" do
    # Pretix::MembershipSync constructs Pretix::Client.new with no arguments,
    # and the real transport must stay the default rather than a test fake.
    client = Pretix::Client.new

    assert_kind_of Pretix::Client, client
    assert_equal HttpTransport, client.instance_variable_get(:@http)
    assert_equal Pretix::Settings, client.instance_variable_get(:@settings)
  end

  test "customers requests the organizer-scoped endpoint with a Token header" do
    client, http = build_client([ page([ customer ]) ])

    client.customers

    request = http.requests.sole
    assert_equal :get, request.method
    assert_equal "https://pretix.eu/api/v1/organizers/eutc/customers/", request.uri
    assert_equal "Token #{TOKEN}", request.headers["Authorization"]
    assert_nil request.body
  end

  test "customers follows next to the end and concatenates every page" do
    second = "https://pretix.eu/api/v1/organizers/eutc/customers/?page=2"
    client, http = build_client([
      page([ customer(identifier: "AAA") ], next_url: second),
      page([ customer(identifier: "BBB") ])
    ])

    identifiers = client.customers.map { |c| c["identifier"] }

    assert_equal %w[AAA BBB], identifiers
    assert_equal second, http.requests.last.uri
  end

  test "customers sends the token on the followed next page too" do
    second = "https://pretix.eu/api/v1/organizers/eutc/customers/?page=2"
    client, http = build_client([ page([ customer ], next_url: second), page([]) ])

    client.customers

    assert_equal "Token #{TOKEN}", http.requests.last.headers["Authorization"]
  end

  test "customer_by_email filters on email and returns the single hash" do
    client, http = build_client([ page([ customer(email: "Alice@Example.com") ]) ])

    found = client.customer_by_email("alice@example.com")

    assert_equal "MG3KL", found["identifier"]
    assert_equal "https://pretix.eu/api/v1/organizers/eutc/customers/?email=alice%40example.com",
                 http.requests.sole.uri
  end

  test "customer_by_email returns nil when pretix matched nobody" do
    client, = build_client([ page([]) ])

    assert_nil client.customer_by_email("nobody@example.com")
  end

  test "customer_by_email raises rather than guessing between two matches" do
    client, = build_client([ page([ customer(identifier: "AAA"), customer(identifier: "BBB") ]) ])

    error = assert_raises(Pretix::Client::Error) { client.customer_by_email("alice@example.com") }

    assert_match(/2 customers/, error.message)
  end

  test "memberships passes both filters through" do
    client, http = build_client([ page([ membership ]) ])

    client.memberships(customer: "MG3KL", membership_type: 225)

    uri = CGI.unescape(http.requests.sole.uri)
    assert_includes uri, "customer=MG3KL"
    assert_includes uri, "membership_type=225"
  end

  test "memberships omits an unset filter rather than sending it blank" do
    client, http = build_client([ page([ membership ]) ])

    client.memberships(membership_type: 225)

    assert_equal "https://pretix.eu/api/v1/organizers/eutc/memberships/?membership_type=225",
                 http.requests.sole.uri
  end

  test "memberships with no filters at all sends no query string" do
    client, http = build_client([ page([ membership ]) ])

    client.memberships

    assert_equal "https://pretix.eu/api/v1/organizers/eutc/memberships/", http.requests.sole.uri
  end

  test "memberships follows pagination" do
    second = "https://pretix.eu/api/v1/organizers/eutc/memberships/?page=2"
    client, = build_client([
      page([ membership(id: 1) ], next_url: second),
      page([ membership(id: 2) ])
    ])

    assert_equal [ 1, 2 ], client.memberships.map { |m| m["id"] }
  end

  test "create_membership posts the payload and returns the created membership" do
    client, http = build_client([ [ 201, membership(id: 77).to_json ] ], writes: true)

    created = client.create_membership(customer: "MG3KL", membership_type: 225,
                                      date_start: Time.zone.parse("2026-08-26 00:00:00"),
                                      date_end: Time.zone.parse("2027-09-21 23:59:59"))

    assert_equal 77, created["id"]
    request = http.requests.sole
    assert_equal :post, request.method
    assert_equal "https://pretix.eu/api/v1/organizers/eutc/memberships/", request.uri
    assert_equal "application/json", request.headers["Content-Type"]

    payload = JSON.parse(request.body)
    assert_equal "MG3KL", payload["customer"]
    assert_equal 225, payload["membership_type"]
    assert_equal "2026-08-26T00:00:00+01:00", payload["date_start"]
    assert_equal "2027-09-21T23:59:59+01:00", payload["date_end"]
  end

  test "create_membership sends a bare Date with an offset, not a naked date" do
    client, http = build_client([ [ 201, membership.to_json ] ], writes: true)

    client.create_membership(customer: "MG3KL", membership_type: 225,
                             date_start: Date.new(2026, 8, 26), date_end: Date.new(2027, 9, 21))

    payload = JSON.parse(http.requests.sole.body)
    assert_equal "2026-08-26T00:00:00+01:00", payload["date_start"]
    assert_equal "2027-09-21T00:00:00+01:00", payload["date_end"]
  end

  test "update_membership patches only date_end" do
    client, http = build_client([ [ 200, membership(id: 77).to_json ] ], writes: true)

    updated = client.update_membership(77, date_end: Time.zone.parse("2026-08-26 12:00:00"))

    assert_equal 77, updated["id"]
    request = http.requests.sole
    assert_equal :patch, request.method
    assert_equal "https://pretix.eu/api/v1/organizers/eutc/memberships/77/", request.uri
    assert_equal({ "date_end" => "2026-08-26T12:00:00+01:00" }, JSON.parse(request.body))
  end

  test "create_membership is suppressed when writes are disabled" do
    client, http = build_client([])

    assert_raises(Pretix::Client::WritesSuppressedError) do
      client.create_membership(customer: "MG3KL", membership_type: 225,
                               date_start: Time.current, date_end: 1.year.from_now)
    end

    assert_empty http.requests, "a suppressed write must not reach pretix at all"
  end

  test "update_membership is suppressed when writes are disabled" do
    client, http = build_client([])

    assert_raises(Pretix::Client::WritesSuppressedError) do
      client.update_membership(77, date_end: Time.current)
    end

    assert_empty http.requests
  end

  test "reads stay live when writes are disabled" do
    client, = build_client([ page([ customer ]) ])

    assert_equal 1, client.customers.size
  end

  test "401 and 403 raise AuthError" do
    [ 401, 403 ].each do |status|
      client, = build_client([ [ status, { detail: "Invalid token." }.to_json ] ])

      error = assert_raises(Pretix::Client::AuthError) { client.customers }
      assert_match(/#{status}/, error.message)
    end
  end

  test "another non-2xx raises Error carrying the status and the body" do
    client, = build_client([ [ 500, "upstream exploded" ] ])

    error = assert_raises(Pretix::Client::Error) { client.customers }

    assert_match(/500/, error.message)
    assert_match(/upstream exploded/, error.message)
  end

  test "a long failure body is truncated into the message" do
    client, = build_client([ [ 400, "x" * 5_000 ] ])

    error = assert_raises(Pretix::Client::Error) { client.customers }

    assert_operator error.message.length, :<, 500
  end

  test "no raised error carries the API token" do
    [ [ 401, "nope" ], [ 500, "boom" ], [ 200, "<html>not json</html>" ] ].each do |response|
      client, = build_client([ response ])

      error = assert_raises(Pretix::Client::Error) { client.customers }
      refute_includes error.message, TOKEN
    end
  end

  test "an unreadable body raises Error rather than a raw JSON::ParserError" do
    client, = build_client([ [ 200, "<html>Gateway</html>" ] ])

    error = assert_raises(Pretix::Client::Error) { client.customers }

    assert_match(/unreadable/, error.message)
  end

  test "a missing token raises AuthError before any request is made" do
    client, http = build_client([], token: nil)

    assert_raises(Pretix::Client::AuthError) { client.customers }
    assert_empty http.requests
  end

  # --- subevents -------------------------------------------------------------
  #
  # A Bedlam show is a pretix event SERIES, so its performances are subevents of
  # the series named by Event#pretix_slug. This is the read Pretix::PerformanceSync
  # is built on.

  test "subevents are read from the series named by the event slug" do
    client, http = build_client([ page([ subevent ]) ])

    results = client.subevents("hamlet")

    assert_equal [ 42 ], results.map { |row| row["id"] }
    assert_includes http.requests.first.uri, "organizers/eutc/events/hamlet/subevents/"
  end

  test "subevents ask for web availability, or nothing can tell a sold-out date" do
    client, http = build_client([ page([ subevent ]) ])

    client.subevents("hamlet")

    assert_includes http.requests.first.uri, "with_availability_for=web"
  end

  test "subevents follow pagination like every other list" do
    next_url = "https://pretix.eu/api/v1/organizers/eutc/events/hamlet/subevents/?page=2"
    client, = build_client([ page([ subevent(id: 1) ], next_url: next_url),
                             page([ subevent(id: 2) ]) ])

    assert_equal [ 1, 2 ], client.subevents("hamlet").map { |row| row["id"] }
  end

  test "a series pretix does not know raises NotFoundError, not a bare Error" do
    # The sync distinguishes these: a wrong slug is a fact about our data and
    # must leave the event's existing performances standing, untouched.
    client, = build_client([ [ 404, { detail: "Not found." }.to_json ] ])

    assert_raises(Pretix::Client::NotFoundError) { client.subevents("nope") }
  end

  test "reading subevents needs no write permission" do
    client, = build_client([ page([]) ], writes: false)

    assert_empty client.subevents("hamlet")
  end

  def subevent(id: 42, date_from: "2026-10-10T19:30:00+01:00")
    { id: id, name: { "en" => "Performance" }, event: "hamlet", active: true, is_public: true,
      date_from: date_from, date_to: nil, date_admission: nil, best_availability_state: 100 }
  end

  test "events_readable? is true when the organizer's events can be listed" do
    client, = build_client([ page([]) ])

    assert client.events_readable?
  end

  test "events_readable? is false when the token is refused" do
    # This is what separates a shop that does not exist yet from a dead token:
    # pretix answers 403 for both on the per-event endpoint.
    client, = build_client([ [ 403, { detail: "Permission denied." }.to_json ] ])

    assert_not client.events_readable?
  end

  test "events_readable? is false rather than raising when pretix is unreachable" do
    client, = build_client([ [ 500, "gateway error" ] ])

    assert_not client.events_readable?, "an unconfirmed token is not a working one"
  end
end
