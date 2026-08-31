require "test_helper"

class EventOccurrenceTest < ActiveSupport::TestCase
  setup do
    @event = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
  end

  def occurrence_at(time, **attributes)
    EventOccurrence.new(event: @event, starts_at: time, **attributes)
  end

  test "requires a start time" do
    occurrence = occurrence_at(nil)

    assert_not occurrence.valid?
    assert occurrence.errors[:starts_at].present?
  end

  test "an end time is optional" do
    assert occurrence_at(Time.zone.local(2026, 3, 3, 19, 30)).valid?
  end

  test "rejects an end time at or before the start" do
    occurrence = occurrence_at(Time.zone.local(2026, 3, 3, 19, 30),
                               ends_at: Time.zone.local(2026, 3, 3, 18, 0))

    assert_not occurrence.valid?
    assert occurrence.errors[:ends_at].present?
  end

  # The run dates and the performance list are two statements of the same fact.
  # Without this they can contradict each other with nothing to catch it.
  test "rejects a start time outside the event's run" do
    [ Time.zone.local(2026, 3, 2, 19, 30), Time.zone.local(2026, 3, 8, 19, 30) ].each do |outside|
      occurrence = occurrence_at(outside)

      assert_not occurrence.valid?, "#{outside} is outside the run and should be rejected"
      assert occurrence.errors[:starts_at].present?
    end
  end

  test "accepts a start time on either end of the run" do
    [ Time.zone.local(2026, 3, 3, 19, 30), Time.zone.local(2026, 3, 7, 19, 30) ].each do |inside|
      assert occurrence_at(inside).valid?, "#{inside} is inside the run and should be accepted"
    end
  end

  test "accepts the known access flags" do
    occurrence = occurrence_at(Time.zone.local(2026, 3, 4, 19, 30), access_flags: %w[relaxed captioned])

    assert occurrence.valid?
    assert occurrence.access_flag?(:relaxed)
    assert_not occurrence.access_flag?(:bsl)
  end

  test "rejects an access flag outside the allow-list" do
    occurrence = occurrence_at(Time.zone.local(2026, 3, 4, 19, 30), access_flags: %w[relaxed interpretive_dance])

    assert_not occurrence.valid?
    assert occurrence.errors[:access_flags].present?
  end

  test "access flags read as an empty list when never set" do
    occurrence = EventOccurrence.create!(event: @event, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal [], occurrence.reload.access_flags
    assert_not occurrence.access_flag?(:relaxed)
  end

  test "access flags drop blanks and duplicates" do
    occurrence = occurrence_at(Time.zone.local(2026, 3, 4, 19, 30), access_flags: [ "", "relaxed", "relaxed", " " ])

    assert_equal %w[relaxed], occurrence.access_flags
  end

  # "bsl".humanize is "Bsl", so the labels are written out rather than derived --
  # and the stored values are derived from THEM, so the two cannot drift.
  test "every access flag has a written label" do
    assert_equal EventOccurrence::ACCESS_FLAGS, EventOccurrence::ACCESS_FLAG_LABELS.keys
    assert_equal "BSL interpreted", EventOccurrence::ACCESS_FLAG_LABELS.fetch("bsl")
  end

  test "access_flag_labels lists the set flags in the constant's order" do
    occurrence = occurrence_at(Time.zone.local(2026, 3, 4, 19, 30), access_flags: %w[relaxed preview])

    assert_equal [ "Preview", "Relaxed" ], occurrence.access_flag_labels
  end

  # The nested form always posts one untouched blank row from its template, and
  # its access_flags check_boxes send [""] -- which is not blank, so :all_blank
  # never fired and saving the event failed with "starts at must not be blank".
  test "an untouched blank row from the form is dropped, not saved" do
    assert_difference "EventOccurrence.count", 0 do
      assert @event.update(event_occurrences_attributes: {
        "0" => { "starts_at" => "", "ends_at" => "", "note" => "", "access_flags" => [ "" ] }
      }), @event.errors.full_messages.to_sentence
    end
  end

  test "a row with a start time is still saved" do
    assert_difference "EventOccurrence.count", 1 do
      @event.update!(event_occurrences_attributes: {
        "0" => { "starts_at" => Time.zone.local(2026, 3, 4, 19, 30), "access_flags" => [ "" ] }
      })
    end
  end

  test "occurrences come back in time order regardless of creation order" do
    late = EventOccurrence.create!(event: @event, starts_at: Time.zone.local(2026, 3, 6, 19, 30))
    early = EventOccurrence.create!(event: @event, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal [ early.id, late.id ], @event.reload.event_occurrences.map(&:id)
  end

  test "destroying the event destroys its occurrences" do
    EventOccurrence.create!(event: @event, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_difference "EventOccurrence.count", -1 do
      @event.destroy
    end
  end

  # --- pretix sync -----------------------------------------------------------

  test "an occurrence with a pretix subevent id is the sync's to manage" do
    assert occurrence_at(Time.zone.local(2026, 3, 3, 19, 30), pretix_subevent_id: 42).pretix_synced?
  end

  test "an occurrence typed by hand is not, which is what keeps the sync off it" do
    assert_not occurrence_at(Time.zone.local(2026, 3, 3, 19, 30)).pretix_synced?
  end

  test "a per-occurrence admission time wins over the event-wide doors offset" do
    @event.update!(doors_open_minutes_before: 30)
    occurrence = occurrence_at(Time.zone.local(2026, 3, 3, 19, 30),
                               admission_at: Time.zone.local(2026, 3, 3, 18, 45))

    assert_equal Time.zone.local(2026, 3, 3, 18, 45), occurrence.doors_open_at
  end

  test "without an admission time the event-wide doors offset still applies" do
    @event.update!(doors_open_minutes_before: 30)

    assert_equal Time.zone.local(2026, 3, 3, 19, 0),
                 occurrence_at(Time.zone.local(2026, 3, 3, 19, 30)).doors_open_at
  end

  test "sold out and cancelled default to false rather than nil" do
    # The columns are nullable -- every row predating the sync reads back nil --
    # and every view would otherwise have to know that.
    occurrence = occurrence_at(Time.zone.local(2026, 3, 3, 19, 30))

    assert_not occurrence.sold_out?
    assert_not occurrence.cancelled?
  end

  test "two occurrences cannot claim the same pretix subevent" do
    time = Time.zone.local(2026, 3, 3, 19, 30)
    occurrence_at(time, pretix_subevent_id: 42).save!

    assert_raises(ActiveRecord::RecordNotUnique) do
      occurrence_at(time + 1.day, pretix_subevent_id: 42).save!
    end
  end

  test "hand-typed occurrences are unconstrained by that uniqueness" do
    time = Time.zone.local(2026, 3, 3, 19, 30)
    occurrence_at(time).save!

    assert_nothing_raised { occurrence_at(time + 1.day).save! }
  end
end
