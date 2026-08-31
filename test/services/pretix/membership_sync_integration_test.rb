# frozen_string_literal: true

require "test_helper"

##
# MembershipSync and Client are unit-tested apart, each against a fake of the
# other. That leaves exactly one thing unproven: that they agree. These tests
# wire the REAL sync to the REAL client and fake only the HTTP transport, so a
# renamed keyword, a changed arity or a misread response shape fails here rather
# than against live pretix on the first member the reconcile touches.
#
# They assert on the requests that reach the wire, because that — not a return
# value — is what pretix will actually receive.
class Pretix::MembershipSyncIntegrationTest < ActiveSupport::TestCase
  # Writes are gated to production, so every test here injects a settings double
  # with the gate open. See Pretix::Settings.writes_enabled?.
  WritingSettings = Struct.new(:writes_enabled) do
    def writes_enabled? = writes_enabled
  end

  CUSTOMER = "6FD51BC"

  setup do
    @user = FactoryBot.create(:user, email: "member@example.com")
    @user.add_role :member
  end

  test "creates a membership for an entitled user through the real client" do
    http = FakeHttp.new([
      page([ customer_row ]),
      page([]),
      [ 201, membership_row(id: 1, date_end: "2027-09-21T23:59:59+01:00").to_json ]
    ])

    assert_equal :created, sync(http).sync_user(@user)

    create = http.requests.last
    assert_equal :post, create.method
    assert_match %r{/organizers/eutc/memberships/\z}, URI(create.uri).path

    body = JSON.parse(create.body)
    assert_equal CUSTOMER, body["customer"]
    assert_equal Pretix::Settings::MEMBERSHIP_TYPE_ID, body["membership_type"]
    # End of the next academic year plus three weeks. Asserted as a date rather
    # than a literal so this does not have to be rewritten every September.
    assert_equal expected_horizon, Time.zone.parse(body["date_end"]).to_date
    assert_operator Time.zone.parse(body["date_start"]), :<=, Time.zone.now
  end

  test "expires every membership of a user who has lost the role" do
    @user.remove_role :member

    http = FakeHttp.new([
      page([ customer_row ]),
      page([ membership_row(id: 11, date_start: "2025-09-15T00:00:00+01:00"),
             membership_row(id: 12, date_start: "2026-09-15T00:00:00+01:00") ]),
      [ 200, membership_row(id: 11).to_json ],
      [ 200, membership_row(id: 12).to_json ]
    ])

    assert_equal :expired, sync(http).sync_user(@user)

    patches = http.requests.select { |request| request.method == :patch }
    assert_equal 2, patches.size, "both the canonical record and the duplicate must be expired"
    patches.each do |patch|
      assert_operator Time.zone.parse(JSON.parse(patch.body)["date_end"]), :<=, Time.zone.now
    end
  end

  test "collapses duplicates onto the widest window and extends only that one" do
    http = FakeHttp.new([
      page([ customer_row ]),
      # The earliest date_start is the canonical record; the other is collapsed.
      page([ membership_row(id: 21, date_start: "2026-09-15T00:00:00+01:00", date_end: 6.weeks.from_now.iso8601),
             membership_row(id: 22, date_start: "2022-09-01T00:00:00+01:00", date_end: 6.weeks.from_now.iso8601) ]),
      [ 200, membership_row(id: 22).to_json ],
      [ 200, membership_row(id: 21).to_json ]
    ])

    sync(http).sync_user(@user)

    patched = http.requests.select { |request| request.method == :patch }
                   .to_h { |request| [ URI(request.uri).path[%r{/(\d+)/\z}, 1].to_i,
                                       Time.zone.parse(JSON.parse(request.body)["date_end"]) ] }

    assert_equal expected_horizon, patched.fetch(22).to_date, "the widest window is the one extended"
    assert_operator patched.fetch(21), :<=, Time.zone.now, "the duplicate is expired"
  end

  test "writes nothing when the gate is closed, and says so rather than reporting success" do
    http = FakeHttp.new([ page([ customer_row ]), page([]) ])
    closed = Pretix::MembershipSync.new(
      client: Pretix::Client.new(token: "t", http: http, settings: WritingSettings.new(false),
                                 sleeper: ->(_seconds) { })
    )

    assert_equal :suppressed, closed.sync_user(@user)
    assert_empty http.requests.select { |request| [ :post, :patch ].include?(request.method) }
  end

  test "matches a customer whose claim predates the sms.ed.ac.uk email rewrite" do
    # pretix stores the email claim from the member's FIRST login, and 30 live
    # customers still carry the @sms form that User.normalizes rewrites. Merely
    # downcasing here found no User and silently denied them member pricing.
    student = FactoryBot.create(:user, email: "s1234567@sms.ed.ac.uk")
    student.add_role :member
    assert_equal "s1234567@ed.ac.uk", student.reload.email, "the model rewrites the domain on save"

    http = FakeHttp.new([
      page([ { "identifier" => CUSTOMER, "email" => "s1234567@sms.ed.ac.uk",
               "external_identifier" => "s1234567@sms.ed.ac.uk" } ]),
      page([]),
      [ 201, membership_row(id: 31).to_json ]
    ])

    assert_equal :created, sync(http).sync_user(student)
  end

  test "an anonymized customer, with no identity of any kind, is left alone" do
    # pretix's anonymize action clears email and external_identifier both; 189
    # such records exist in the live shop, all inactive and unverified.
    # The fake hands the record back regardless of the query, so this exercises
    # the guard rather than the lookup: a record with no identity of any kind
    # cannot be confirmed as this person's, so it is left alone.
    blank = customer_row.merge("external_identifier" => nil, "email" => nil)
    http = FakeHttp.new([ page([ blank ]) ])

    assert_equal :no_identifier, sync(http).sync_user(@user)
    assert_equal 1, http.requests.size, "it must not go on to read or write memberships"
  end

  private

  def sync(http)
    Pretix::MembershipSync.new(
      client: Pretix::Client.new(token: "t", http: http, settings: WritingSettings.new(true),
                                 sleeper: ->(_seconds) { })
    )
  end

  # An academic year starting in Y ends 31 Aug of Y+1, so the NEXT one ends in
  # Y+2 — then three weeks of slack for the manual September rollover.
  def expected_horizon
    start_year = ApplicationController.helpers.date_to_academic_year(Date.current)
    Date.new(start_year + 2, 8, 31) + 3.weeks
  end

  def page(results)
    [ 200, { "count" => results.size, "next" => nil, "results" => results }.to_json ]
  end

  def customer_row
    { "identifier" => CUSTOMER, "email" => @user.email, "external_identifier" => @user.email }
  end

  # date_end is RELATIVE, never a literal. A hardcoded one silently becomes
  # "already expired" on the day it passes, and the sync then correctly reports
  # :unchanged while the test still expects :expired. The old literal was
  # 2026-08-31, and that is exactly what happened on 2026-08-31.
  def membership_row(id:, date_start: "2025-09-15T00:00:00+01:00", date_end: 1.year.from_now.iso8601)
    { "id" => id, "customer" => CUSTOMER, "membership_type" => Pretix::Settings::MEMBERSHIP_TYPE_ID,
      "date_start" => date_start, "date_end" => date_end, "testmode" => false }
  end
end
