require "test_helper"

class Pretix::ClientTest < ActiveSupport::TestCase
  TOKEN = "s3cr3t-pretix-token".freeze

  # The transport seam is a class_attribute, so it carries an instance writer
  # too; setting it on the instance keeps one test from leaking a fake into
  # every later Pretix::Client in the same parallel worker.
  def build_client(responses, organizer: "eutc", token: TOKEN)
    http = FakeHttp.new(responses)
    client = Pretix::Client.new(organizer: organizer, token: token)
    client.transport = http
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

  # Writes are gated on Settings.writes_enabled?, which reads ENV outside
  # production. A dev shell may already export it, so both directions are forced.
  def with_writes(enabled)
    previous = ENV["PRETIX_ENABLE_WRITES"]
    ENV["PRETIX_ENABLE_WRITES"] = enabled ? "1" : nil
    yield
  ensure
    ENV["PRETIX_ENABLE_WRITES"] = previous
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
    client, http = build_client([ [ 201, membership(id: 77).to_json ] ])

    created = with_writes(true) do
      client.create_membership(customer: "MG3KL", membership_type: 225,
                               date_start: Time.zone.parse("2026-08-26 00:00:00"),
                               date_end: Time.zone.parse("2027-09-21 23:59:59"))
    end

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
    client, http = build_client([ [ 201, membership.to_json ] ])

    with_writes(true) do
      client.create_membership(customer: "MG3KL", membership_type: 225,
                               date_start: Date.new(2026, 8, 26), date_end: Date.new(2027, 9, 21))
    end

    payload = JSON.parse(http.requests.sole.body)
    assert_equal "2026-08-26T00:00:00+01:00", payload["date_start"]
    assert_equal "2027-09-21T00:00:00+01:00", payload["date_end"]
  end

  test "update_membership patches only date_end" do
    client, http = build_client([ [ 200, membership(id: 77).to_json ] ])

    updated = with_writes(true) do
      client.update_membership(77, date_end: Time.zone.parse("2026-08-26 12:00:00"))
    end

    assert_equal 77, updated["id"]
    request = http.requests.sole
    assert_equal :patch, request.method
    assert_equal "https://pretix.eu/api/v1/organizers/eutc/memberships/77/", request.uri
    assert_equal({ "date_end" => "2026-08-26T12:00:00+01:00" }, JSON.parse(request.body))
  end

  test "create_membership is suppressed when writes are disabled" do
    client, http = build_client([])

    with_writes(false) do
      assert_raises(Pretix::Client::WritesSuppressedError) do
        client.create_membership(customer: "MG3KL", membership_type: 225,
                                 date_start: Time.current, date_end: 1.year.from_now)
      end
    end

    assert_empty http.requests, "a suppressed write must not reach pretix at all"
  end

  test "update_membership is suppressed when writes are disabled" do
    client, http = build_client([])

    with_writes(false) do
      assert_raises(Pretix::Client::WritesSuppressedError) do
        client.update_membership(77, date_end: Time.current)
      end
    end

    assert_empty http.requests
  end

  test "reads stay live when writes are disabled" do
    client, = build_client([ page([ customer ]) ])

    with_writes(false) { assert_equal 1, client.customers.size }
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
end
