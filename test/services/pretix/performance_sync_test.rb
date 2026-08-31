require "test_helper"

##
# Pretix::PerformanceSync brings one event's performances in line with its pretix
# series. The ownership model is the whole design: pretix owns only the rows it
# created, and the producer's own columns are never written.
##
class Pretix::PerformanceSyncTest < ActiveSupport::TestCase
  # Stands in for Pretix::Client. This suite has no mocking library, so an
  # outbound client is faked and injected, as the membership sync's tests do.
  class FakeClient
    attr_reader :slugs

    def initialize(rows: [], error: nil)
      @rows = rows
      @error = error
      @slugs = []
    end

    def subevents(slug, **)
      @slugs << slug
      raise @error if @error

      @rows
    end
  end

  setup do
    @event = FactoryBot.create(:show, slug: "hamlet",
                                      start_date: Date.new(2026, 3, 3),
                                      end_date: Date.new(2026, 3, 7),
                                      pretix_sync_performances: true)
  end

  def subevent(id: 42, date_from: "2026-03-04T19:30:00+00:00", **overrides)
    { "id" => id, "date_from" => date_from, "date_to" => nil, "date_admission" => nil,
      "active" => true, "is_public" => true, "best_availability_state" => 100 }.merge(overrides.stringify_keys)
  end

  def sync(rows: [], error: nil)
    client = FakeClient.new(rows: rows, error: error)
    [ Pretix::PerformanceSync.new(client: client).call(@event), client ]
  end

  def occurrence!(starts_at:, **attributes)
    @event.event_occurrences.create!(starts_at: starts_at, **attributes)
  end

  # --- creating --------------------------------------------------------------

  test "a subevent with no matching row becomes a performance" do
    result, client = sync(rows: [ subevent ])

    assert_equal [ "hamlet" ], client.slugs, "the series is named by Event#pretix_slug"
    assert_equal 1, result.created
    occurrence = @event.event_occurrences.reload.sole
    assert_equal 42, occurrence.pretix_subevent_id
    assert_equal Time.zone.local(2026, 3, 4, 19, 30), occurrence.starts_at
  end

  test "the slug override wins, as it does everywhere else pretix is addressed" do
    @event.update!(pretix_slug_override: "hamlet-2026")

    _result, client = sync(rows: [ subevent ])

    assert_equal [ "hamlet-2026" ], client.slugs
  end

  test "the end and admission times come across when pretix states them" do
    sync(rows: [ subevent(date_to: "2026-03-04T22:00:00+00:00",
                          date_admission: "2026-03-04T19:00:00+00:00") ])

    occurrence = @event.event_occurrences.reload.sole

    assert_equal Time.zone.local(2026, 3, 4, 22, 0), occurrence.ends_at
    assert_equal Time.zone.local(2026, 3, 4, 19, 0), occurrence.admission_at
  end

  # --- updating --------------------------------------------------------------

  test "a moved performance moves, rather than being duplicated" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    result, = sync(rows: [ subevent(date_from: "2026-03-05T20:00:00+00:00") ])

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal Time.zone.local(2026, 3, 5, 20, 0), @event.event_occurrences.reload.sole.starts_at
  end

  # This is the feature: tick the box, and still tag the relaxed night.
  test "the producer's own columns survive a sync untouched" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42,
                access_flags: [ "relaxed", "captioned" ], note: "BSL by arrangement", cancelled: true)

    sync(rows: [ subevent(date_from: "2026-03-05T20:00:00+00:00") ])

    occurrence = @event.event_occurrences.reload.sole

    assert_equal [ "relaxed", "captioned" ], occurrence.access_flags
    assert_equal "BSL by arrangement", occurrence.note
    assert occurrence.cancelled?, "cancelled is a human statement; the sync must never clear it"
  end

  # --- hand-typed rows -------------------------------------------------------

  test "a hand-typed performance is left alone, so a free preview still shows" do
    hand_typed = occurrence!(starts_at: Time.zone.local(2026, 3, 3, 19, 30), note: "Preview")

    result, = sync(rows: [ subevent ])

    assert_equal 0, result.destroyed
    assert_predicate hand_typed.reload, :persisted?
    assert_equal 2, @event.event_occurrences.reload.count
  end

  # --- deleting --------------------------------------------------------------

  test "a synced row whose subevent is gone is destroyed" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    result, = sync(rows: [])

    assert_equal 1, result.destroyed
    assert_empty @event.event_occurrences.reload
  end

  # The one case where deleting would erase something a producer told the public.
  test "a cancelled row survives its subevent disappearing" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42, cancelled: true)

    result, = sync(rows: [])

    assert_equal 0, result.destroyed
    assert_equal 1, result.kept
    assert_equal 42, @event.event_occurrences.reload.sole.pretix_subevent_id,
                 "keeping the id lets the row reattach if the date returns to pretix"
  end

  test "a subevent hidden in the shop is treated as gone" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    result, = sync(rows: [ subevent(is_public: false) ])

    assert_equal 1, result.destroyed
    assert_empty @event.event_occurrences.reload
  end

  test "a date not on sale is still a performance" do
    # active:false means the shop is closed for that date, not that it is off.
    # pretix has presale_start for "not on sale yet", and no cancellation concept
    # at all -- inferring one here is what would put a wrong CANCELLED on a page.
    result, = sync(rows: [ subevent(active: false) ])

    assert_equal 1, result.created
  end

  test "emptying a whole series is reported, since it is also what a bad slug looks like" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    result, = sync(rows: [])

    assert result.emptied_series?
  end

  # --- sold out --------------------------------------------------------------

  test "availability below 100 reads as sold out" do
    sync(rows: [ subevent(best_availability_state: 20) ])

    assert_predicate @event.event_occurrences.reload.sole, :sold_out?
  end

  test "unknown availability never reads as sold out" do
    # pretix sends null for "status unknown". Telling someone they cannot buy a
    # ticket they can is the more costly direction of this error.
    sync(rows: [ subevent(best_availability_state: nil) ])

    assert_not_predicate @event.event_occurrences.reload.sole, :sold_out?
  end

  test "a date that comes back on sale stops reading as sold out" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42, sold_out: true)

    sync(rows: [ subevent ])

    assert_not_predicate @event.event_occurrences.reload.sole, :sold_out?
  end

  # --- run dates -------------------------------------------------------------

  test "the run widens to cover a date pretix is selling beyond it" do
    sync(rows: [ subevent(date_from: "2026-03-09T19:30:00+00:00") ])

    assert_equal Date.new(2026, 3, 9), @event.reload.end_date
    assert_equal 1, @event.event_occurrences.count,
                 "widening first is what lets the occurrence pass starts_at_within_run"
  end

  test "the run widens backwards too" do
    sync(rows: [ subevent(date_from: "2026-03-01T19:30:00+00:00") ])

    assert_equal Date.new(2026, 3, 1), @event.reload.start_date
  end

  test "the run is never narrowed" do
    # A run may legitimately be wider than its ticketed dates -- a get-in, a
    # free preview -- but never narrower than a date the shop is selling.
    sync(rows: [ subevent(date_from: "2026-03-05T19:30:00+00:00") ])
    @event.reload

    assert_equal Date.new(2026, 3, 3), @event.start_date
    assert_equal Date.new(2026, 3, 7), @event.end_date
  end

  # --- failure ---------------------------------------------------------------

  # --- a series that does not exist yet --------------------------------------
  #
  # Ticking the box before building the shop is the natural order to work in, so
  # "pretix has never heard of this slug" is a waiting state, not a failure. It
  # is recorded and shown in the admin; nothing is raised and nothing reported,
  # or every such event would alert every fifteen minutes for its whole run.

  test "a series pretix does not know is recorded as waiting, not raised" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    result = nil
    assert_nothing_raised { result, = sync(error: Pretix::Client::NotFoundError.new("gone")) }

    assert_predicate result, :missing_series?
    assert_equal 1, @event.event_occurrences.reload.count, "existing performances must stand"
    assert @event.reload.pretix_sync_error.present?
    assert_nil @event.pretix_synced_at
  end

  test "a series appearing later clears the warning" do
    @event.update_columns(pretix_sync_error: "No ticket shop found for hamlet yet.")

    sync(rows: [ subevent ])
    @event.reload

    assert_nil @event.pretix_sync_error
    assert @event.pretix_synced_at.present?
  end

  test "a successful sync stamps when it last read the series" do
    freeze_time do
      sync(rows: [ subevent ])

      assert_equal Time.current.to_i, @event.reload.pretix_synced_at.to_i
    end
  end

  test "recording the wait does not add a paper trail version every fifteen minutes" do
    assert_no_difference -> { @event.versions.count } do
      sync(error: Pretix::Client::NotFoundError.new("gone"))
    end
  end

  test "a transport failure writes nothing, rather than blanking a run" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 42)

    assert_raises(Pretix::Client::Error) { sync(error: Pretix::Client::Error.new("timeout")) }

    assert_equal 1, @event.event_occurrences.reload.count
  end

  test "an unreadable date is skipped rather than taking the rest of the run with it" do
    result, = sync(rows: [ subevent(id: 1, date_from: nil), subevent(id: 2) ])

    assert_equal 1, result.created
    assert_equal 1, result.skipped
    assert_equal [ 2 ], @event.event_occurrences.reload.map(&:pretix_subevent_id)
  end

  # --- adopting a hand-typed row ---------------------------------------------
  #
  # A producer who typed their dates in before the box was ticked would otherwise
  # get every night twice: theirs and pretix's. An exact match is the same
  # performance, so the sync takes the existing row over rather than adding one.

  test "a hand-typed performance at the same time is adopted, not duplicated" do
    typed = occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    result, = sync(rows: [ subevent ])

    assert_equal 1, result.adopted
    assert_equal 0, result.created
    assert_equal [ typed.id ], @event.event_occurrences.reload.map(&:id)
    assert_equal 42, typed.reload.pretix_subevent_id
  end

  test "adopting keeps everything the producer put on that row" do
    typed = occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30),
                        access_flags: [ "captioned" ], note: "Signed by arrangement")

    sync(rows: [ subevent ])
    typed.reload

    assert_equal [ "captioned" ], typed.access_flags
    assert_equal "Signed by arrangement", typed.note
  end

  test "a hand-typed performance at a different time is left as its own row" do
    # Not the same performance: a matinee, a preview, or a producer who has the
    # curtain time wrong. Either way it is not the sync's to merge away.
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 14, 0))

    result, = sync(rows: [ subevent ])

    assert_equal 0, result.adopted
    assert_equal 1, result.created
    assert_equal 2, @event.event_occurrences.reload.count
  end

  test "a row already owned by another subevent is never adopted away from it" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30), pretix_subevent_id: 99)

    result, = sync(rows: [ subevent ])

    assert_equal 0, result.adopted
    assert_equal 1, result.created
  end

  test "two subevents cannot adopt the same hand-typed row" do
    occurrence!(starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    result, = sync(rows: [ subevent(id: 1), subevent(id: 2) ])

    assert_equal 1, result.adopted
    assert_equal 1, result.created
    assert_equal 2, @event.event_occurrences.reload.count
  end
end
