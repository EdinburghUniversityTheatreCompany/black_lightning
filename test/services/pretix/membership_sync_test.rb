require "test_helper"

class Pretix::MembershipSyncTest < ActiveSupport::TestCase
  include HoneybadgerTestHelpers

  # The suite has no mocking library, so the client seam takes a hand-written
  # fake. It MUTATES its own store on every write, which is what lets a test
  # assert that a second reconcile pass finds nothing left to do.
  class FakeClient
    WRITE_CALLS = %i[create_membership update_membership].freeze

    attr_reader :calls

    def initialize(customers: [], memberships: [], raises: nil)
      @customers = customers
      @memberships = memberships
      @raises = raises
      @calls = []
      @next_id = 9000
    end

    def customers
      record(:customers)
      @customers.deep_dup
    end

    def customer(identifier)
      record(:customer, identifier)
      return nil if identifier.blank?

      @customers.find { |c| c["identifier"] == identifier }&.deep_dup
    end

    def customer_by_email(email)
      record(:customer_by_email, email)
      @customers.find { |customer| customer["email"].to_s.casecmp?(email.to_s) }&.deep_dup
    end

    def memberships(customer: nil, membership_type: nil)
      record(:memberships, customer, membership_type)
      @memberships.select do |membership|
        (customer.nil? || membership["customer"] == customer) &&
          (membership_type.nil? || membership["membership_type"] == membership_type)
      end.deep_dup
    end

    def create_membership(customer:, membership_type:, date_start:, date_end:)
      raise @raises if @raises

      record(:create_membership, customer, date_start, date_end)
      created = { "id" => (@next_id += 1), "customer" => customer, "membership_type" => membership_type,
                  "date_start" => date_start.iso8601, "date_end" => date_end.iso8601 }
      @memberships << created
      created.deep_dup
    end

    def update_membership(id, date_end:)
      raise @raises if @raises

      record(:update_membership, id, date_end)
      stored = @memberships.find { |membership| membership["id"] == id } or raise "no membership #{id}"
      stored["date_end"] = date_end.iso8601
      stored.deep_dup
    end

    # Only the calls that changed something in pretix.
    def writes = @calls.select { |call| WRITE_CALLS.include?(call.first) }

    def reads = @calls.reject { |call| WRITE_CALLS.include?(call.first) }

    private

    def record(*call) = @calls << call
  end

  NOW = "2026-08-26 10:00:00"

  # End of the NEXT academic year (2026/27 ends 31 Aug 2027) plus three weeks.
  HORIZON = "2027-09-21T23:59:59+01:00"

  setup do
    travel_to Time.zone.parse(NOW)
  end

  def customer_hash(email, identifier: "cust-#{email}", external_identifier: email)
    { "identifier" => identifier, "email" => email, "external_identifier" => external_identifier }
  end

  def membership_hash(id:, customer:, date_start:, date_end:,
                      membership_type: Pretix::Settings::MEMBERSHIP_TYPE_ID)
    { "id" => id, "customer" => customer, "membership_type" => membership_type,
      "date_start" => date_start, "date_end" => date_end }
  end

  def member = users(:member)

  def non_member = users(:user)

  def horizon = Time.zone.parse(HORIZON)

  # --- the horizon -----------------------------------------------------------

  test "the end date is the end of the next academic year plus three weeks" do
    assert_equal horizon, Pretix::MembershipSync.membership_end

    travel_to Time.zone.parse("2026-10-01 09:00")
    assert_equal Time.zone.parse("2028-09-21T23:59:59+01:00"), Pretix::MembershipSync.membership_end
  end

  # --- sync_user -------------------------------------------------------------

  test "creates one membership for a member who has none" do
    client = FakeClient.new(customers: [ customer_hash(member.email) ])
    sync = Pretix::MembershipSync.new(client: client)

    assert_equal :created, sync.sync_user(member)
    assert_equal [ [ :create_membership, "cust-#{member.email}", Time.zone.parse("2026-08-26 00:00"), horizon ] ],
                 client.writes
  end

  test "a life member is entitled just as a member is" do
    life_member = users(:iolanthe_faerie)
    life_member.add_role("life member")
    client = FakeClient.new(customers: [ customer_hash(life_member.email) ])

    assert_equal :created, Pretix::MembershipSync.new(client: client).sync_user(life_member)
  end

  test "extends a membership whose end date is inside the refresh window" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00",
                                     date_end: "2026-08-31T23:59:59+01:00") ]
    )

    assert_equal :extended, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_equal [ [ :update_membership, 1, horizon ] ], client.writes
  end

  test "leaves a fresh membership alone, and never moves date_start" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{member.email}",
                                     date_start: "2024-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    assert_equal :unchanged, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_empty client.writes
  end

  test "leaves a membership ending beyond the refresh window alone" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00",
                                     date_end: "2028-06-01T23:59:59+01:00") ]
    )

    assert_equal :unchanged, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_empty client.writes
  end

  test "expires the membership of someone who has lost the role" do
    client = FakeClient.new(
      customers: [ customer_hash(non_member.email) ],
      memberships: [ membership_hash(id: 7, customer: "cust-#{non_member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    assert_equal :expired, Pretix::MembershipSync.new(client: client).sync_user(non_member)
    assert_equal [ [ :update_membership, 7, Time.zone.now ] ], client.writes
  end

  test "does not touch a membership that has already lapsed" do
    client = FakeClient.new(
      customers: [ customer_hash(non_member.email) ],
      memberships: [ membership_hash(id: 7, customer: "cust-#{non_member.email}",
                                     date_start: "2024-09-01T00:00:00+01:00",
                                     date_end: "2025-08-31T23:59:59+01:00") ]
    )

    assert_equal :unchanged, Pretix::MembershipSync.new(client: client).sync_user(non_member)
    assert_empty client.writes
  end

  test "collapses duplicates onto the record with the earliest date_start" do
    identifier = "cust-#{member.email}"
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [
        membership_hash(id: 2, customer: identifier, date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON),
        membership_hash(id: 1, customer: identifier, date_start: "2023-09-01T00:00:00+01:00", date_end: HORIZON),
        membership_hash(id: 3, customer: identifier, date_start: "2026-01-05T00:00:00+00:00", date_end: HORIZON)
      ]
    )

    assert_equal :deduplicated, Pretix::MembershipSync.new(client: client).sync_user(member)
    # The widest window (id 1) survives untouched; the other two are expired now.
    assert_equal [ [ :update_membership, 2, Time.zone.now ], [ :update_membership, 3, Time.zone.now ] ],
                 client.writes.sort_by { |call| call[1] }
  end

  test "ignores memberships of another type" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{member.email}", membership_type: 99,
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    assert_equal :created, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_equal 1, client.writes.size
    assert_equal :create_membership, client.writes.first.first
  end

  test "a member who has never logged into pretix has no customer to sync" do
    client = FakeClient.new(customers: [ customer_hash("someone.else@example.com") ])

    assert_equal :no_customer, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_empty client.writes
  end

  # A native pretix account — someone who signed up in the shop with a password
  # rather than through SSO — has no external_identifier, and its own email is
  # then the only handle there is. Matching on it is safe because BOTH paths
  # resolve a customer the same way, so the reconcile can find this account again.
  # Members should not have to have used SSO to be recognised.
  test "a native account with no SSO identity is matched on its own email" do
    client = FakeClient.new(customers: [ customer_hash(member.email, external_identifier: nil) ])

    assert_equal :created, Pretix::MembershipSync.new(client: client).sync_user(member)
  end

  test "a customer with neither an SSO identity nor an email is left alone" do
    # pretix's anonymize action clears both; 189 such records exist in the shop.
    anonymized = customer_hash(member.email, external_identifier: nil).merge("email" => nil)
    client = FakeClient.new(customers: [ anonymized ])

    assert_equal :no_customer, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_empty client.writes
  end

  # --- the safety bias -------------------------------------------------------

  test "an unreadable date_start expires nothing" do
    client = FakeClient.new(
      customers: [ customer_hash(non_member.email) ],
      memberships: [ membership_hash(id: 4, customer: "cust-#{non_member.email}",
                                     date_start: nil, date_end: HORIZON) ]
    )

    assert_equal :ambiguous, Pretix::MembershipSync.new(client: client).sync_user(non_member)
    assert_empty client.writes
  end

  # Without this guard the unreadable row is invisible and the member gets a
  # SECOND membership, which is what "one membership, forever" exists to prevent.
  test "an unreadable date_start creates nothing either" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 4, customer: "cust-#{member.email}",
                                     date_start: "not a date", date_end: HORIZON) ]
    )

    assert_equal :ambiguous, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_empty client.writes
  end

  test "an unrecognised customer is never expired" do
    client = FakeClient.new(
      customers: [ customer_hash("ghost@example.com") ],
      memberships: [ membership_hash(id: 5, customer: "cust-ghost@example.com",
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:no_user]
    assert_empty client.writes
  end

  test "an anonymized customer, with no identity of any kind, is never expired" do
    anonymized = customer_hash(non_member.email, external_identifier: nil).merge("email" => nil)
    client = FakeClient.new(
      customers: [ anonymized ],
      memberships: [ membership_hash(id: 6, customer: "cust-#{non_member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:no_identifier]
    assert_empty client.writes
  end

  # --- the stored customer link ----------------------------------------------
  #
  # pretix keys an SSO account on a hash of the email claim, and refuses to let
  # either identifier field be rewritten afterwards, so matching by email is the
  # only way in. The link records what that match found, and everything below is
  # about surviving the email changing later.

  test "the link is recorded the first time a customer is matched by email" do
    client = FakeClient.new(customers: [ customer_hash(member.email) ])

    Pretix::MembershipSync.new(client: client).sync_user(member)

    assert_equal "cust-#{member.email}", member.reload.pretix_customer_identifier
  end

  test "a member who changed their email is still found, through the stored link" do
    member.update_column(:pretix_customer_identifier, "cust-old")
    # The customer still carries the address they first signed in with; the user
    # no longer does. Matching by email would find nobody.
    client = FakeClient.new(customers: [ customer_hash("old@example.com", identifier: "cust-old") ])

    assert_equal :created, Pretix::MembershipSync.new(client: client).sync_user(member)
    assert_equal [ :customer ], client.reads.map(&:first).grep(/customer/), "email lookup must not be needed"
  end

  test "a stale link falls back to email rather than giving up" do
    member.update_column(:pretix_customer_identifier, "cust-deleted")
    client = FakeClient.new(customers: [ customer_hash(member.email) ])

    assert_equal :created, Pretix::MembershipSync.new(client: client).sync_user(member)
  end

  test "a link that still resolves is left alone, even beside a second account" do
    # Someone holding two pretix accounts — an @sms.ed.ac.uk one and its
    # rewritten @ed.ac.uk twin. Both resolve to this user, so whichever the loop
    # reaches second would re-point the link if nothing stopped it.
    #
    # Both accounts are given a membership that already needs no change, so the
    # run SETTLES IN ONE PASS. That matters: with two passes the re-pointing
    # happens and is then undone by the next pass, leaving the stored value
    # looking untouched and hiding the churn completely.
    member.update_column(:pretix_customer_identifier, "cust-linked")
    client = FakeClient.new(
      customers: [
        customer_hash(member.email, identifier: "cust-linked"),
        customer_hash(member.email, identifier: "cust-twin")
      ],
      memberships: [
        membership_hash(id: 1, customer: "cust-linked", date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON),
        membership_hash(id: 2, customer: "cust-twin", date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON)
      ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:passes], "the scenario must settle in one pass or the churn is invisible"
    assert_equal "cust-linked", member.reload.pretix_customer_identifier
  end

  test "a stale link is re-pointed at the customer found by email" do
    # Otherwise this person pays a doomed lookup before the email one, forever.
    member.update_column(:pretix_customer_identifier, "cust-gone")
    client = FakeClient.new(customers: [ customer_hash(member.email) ])

    Pretix::MembershipSync.new(client: client).sync_user(member)

    assert_equal "cust-#{member.email}", member.reload.pretix_customer_identifier
  end

  test "a customer already claimed by another user does not steal the link" do
    other = FactoryBot.create(:user, email: "other@example.com")
    other.update_column(:pretix_customer_identifier, "cust-#{member.email}")
    client = FakeClient.new(customers: [ customer_hash(member.email) ])

    Pretix::MembershipSync.new(client: client).sync_user(member)

    assert_nil member.reload.pretix_customer_identifier
    assert_equal "cust-#{member.email}", other.reload.pretix_customer_identifier
  end

  test "the reconcile matches on the stored link before the email" do
    member.update_column(:pretix_customer_identifier, "cust-old")
    client = FakeClient.new(customers: [ customer_hash("old@example.com", identifier: "cust-old") ])

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:created], "the member must be recognised despite the email not matching"
    assert_equal 0, counts[:no_user]
  end

  # --- reconcile_all ---------------------------------------------------------

  test "reads memberships per customer, never from one list of the whole shop" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email), customer_hash(non_member.email), customer_hash("ghost@example.com") ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{non_member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:created]
    assert_equal 1, counts[:expired]
    assert_equal 1, counts[:no_user]
    assert_equal 2, counts[:passes]

    # One customer list per pass, then one membership read per customer that
    # RESOLVES TO A USER — the ghost costs no membership call. Slicing a single
    # whole-shop membership list would be cheaper and is exactly what this test
    # forbids: pretix pages that list with no unique tiebreaker and silently
    # drops rows, which made a member with a membership look like one with none.
    reads = client.reads.map(&:first)
    assert_equal 2, reads.count(:customers), "one customer list per pass"
    assert_equal 4, reads.count(:memberships), "two resolvable customers, two passes"
    assert_equal :customers, reads.first
  end

  test "a shop that is already correct is one pass and no writes" do
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [ membership_hash(id: 1, customer: "cust-#{member.email}",
                                     date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON) ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:unchanged]
    assert_equal 1, counts[:passes]
    assert_empty client.writes
  end

  test "re-fetches after writing and stops once a pass finds nothing to do" do
    identifier = "cust-#{member.email}"
    client = FakeClient.new(
      customers: [ customer_hash(member.email) ],
      memberships: [
        membership_hash(id: 1, customer: identifier, date_start: "2023-09-01T00:00:00+01:00",
                        date_end: "2026-08-31T23:59:59+01:00"),
        membership_hash(id: 2, customer: identifier, date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON)
      ]
    )

    counts = Pretix::MembershipSync.new(client: client).reconcile_all

    assert_equal 1, counts[:extended]
    assert_equal 1, counts[:duplicates_expired]
    assert_equal 2, counts[:passes]
    # The second pass re-read everything and left the now-correct shop alone.
    assert_equal 2, client.writes.size
  end

  test "the counts hash carries every outcome" do
    counts = Pretix::MembershipSync.new(client: FakeClient.new).reconcile_all

    assert_equal (Pretix::MembershipSync::OUTCOMES + %i[duplicates_expired passes]).sort, counts.keys.sort
    assert_equal 0, counts.except(:passes).values.sum
  end

  # --- the two paths cannot drift --------------------------------------------

  test "sync_user and reconcile_all make exactly the same writes" do
    shop = lambda do
      FakeClient.new(
        customers: [ customer_hash(member.email), customer_hash(non_member.email) ],
        memberships: [
          membership_hash(id: 1, customer: "cust-#{member.email}", date_start: "2025-09-01T00:00:00+01:00",
                          date_end: "2026-08-31T23:59:59+01:00"),
          membership_hash(id: 2, customer: "cust-#{non_member.email}",
                          date_start: "2025-09-01T00:00:00+01:00", date_end: HORIZON)
        ]
      )
    end

    per_user = shop.call
    sync = Pretix::MembershipSync.new(client: per_user)
    sync.sync_user(member)
    sync.sync_user(non_member)

    whole_shop = shop.call
    Pretix::MembershipSync.new(client: whole_shop).reconcile_all

    assert_equal [ [ :update_membership, 1, horizon ], [ :update_membership, 2, Time.zone.now ] ],
                 per_user.writes.sort_by { |call| call[1] }
    assert_equal per_user.writes.sort_by { |call| call[1] }, whole_shop.writes.sort_by { |call| call[1] }
  end

  # --- failures --------------------------------------------------------------

  test "an API failure is reported and counted, not raised" do
    client = FakeClient.new(customers: [ customer_hash(member.email) ],
                            raises: Pretix::Client::Error.new("pretix said no"))

    notices = capture_honeybadger_notices do
      assert_equal :failed, Pretix::MembershipSync.new(client: client).sync_user(member)
    end

    assert_equal 1, notices.size
  end

  test "suppressed writes are counted, not reported" do
    client = FakeClient.new(customers: [ customer_hash(member.email) ],
                            raises: Pretix::Client::WritesSuppressedError.new)

    notices = capture_honeybadger_notices do
      assert_equal :suppressed, Pretix::MembershipSync.new(client: client).sync_user(member)
    end

    assert_empty notices
  end

  test "an auth failure aborts the whole run rather than being counted per customer" do
    client = FakeClient.new(customers: [ customer_hash(member.email) ],
                            raises: Pretix::Client::AuthError.new("401"))

    assert_raises(Pretix::Client::AuthError) { Pretix::MembershipSync.new(client: client).reconcile_all }
  end
end
