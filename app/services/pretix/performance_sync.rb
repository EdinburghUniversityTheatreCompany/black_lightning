# frozen_string_literal: true

module Pretix
  # Brings ONE event's performances in line with its pretix series: each subevent
  # is one dated performance, i.e. an EventOccurrence.
  #
  # Ownership rides on one column:
  #
  #   pretix_subevent_id set   -> pretix's row. Times and availability are
  #                               overwritten every pass; destroyed when the
  #                               subevent goes.
  #   pretix_subevent_id nil   -> typed by hand (a preview, a get-in, a schools
  #                               matinee). Never written or deleted, except when
  #                               adopted by a subevent at exactly the same
  #                               starts_at.
  #
  # +access_flags+, +note+ and +cancelled+ are the producer's on BOTH kinds of row
  # and are never written here.
  #
  # See CLAUDE.md, "Pretix performance sync".
  class PerformanceSync
    # pretix: 100 is "tickets available", below that "sold out or reserved", null
    # "status unknown". Null is deliberately NOT sold out: telling someone they
    # cannot buy a ticket they can is the more costly error.
    AVAILABLE_STATE = 100

    Result = Data.define(:created, :updated, :adopted, :destroyed, :kept, :skipped,
                         :emptied_series, :missing_series) do
      def emptied_series? = emptied_series

      def missing_series? = missing_series

      def any_change? = created.positive? || updated.positive? || adopted.positive? || destroyed.positive?

      def to_h = { created:, updated:, adopted:, destroyed:, kept:, skipped: }
    end

    # What a pass returns when pretix has no such series yet: nothing was read, so
    # nothing changed. Built after Result is defined.
    MISSING_SERIES = Result.new(created: 0, updated: 0, adopted: 0, destroyed: 0, kept: 0,
                                skipped: 0, emptied_series: false, missing_series: true).freeze

    def initialize(client: Client.new)
      @client = client
    end

    # Fetches first and mutates second, so a failed read leaves the run standing
    # rather than blanking it.
    def call(event)
      subevents = fetch(event)

      # EventOccurrence#starts_at_within_run refuses dates outside the run, so
      # widening BEFORE saving is what lets a date pretix sells beyond the entered
      # run save at all.
      widen_run(event, subevents)

      result = apply(event, subevents)
      record_state(event, error: nil)
      result
    rescue Client::NotFoundError
      missing_series(event)
    rescue Client::AuthError
      # pretix answers 403, not 404, for a slug it will not show you, so an unbuilt
      # shop looks exactly like a token that has lost its access. A working token
      # means this event is simply not in pretix yet; one that can read nothing is
      # a real outage and must stay loud.
      raise unless token_working?

      missing_series(event)
    end

    private

    # A waiting state, NOT a failure: ticking the box before building the shop is
    # the natural order to work in. Recorded for the admin page, existing
    # performances stand, nothing is raised, or every such event would alert every
    # fifteen minutes for the length of its run.
    def missing_series(event)
      record_state(event, error: "No pretix ticket shop found for \"#{event.pretix_slug}\" yet. " \
                                 "The dates will sync as soon as one exists.")
      MISSING_SERIES
    end

    # Memoized: the job builds one sync per run, so a season of unbuilt shops costs
    # one extra request rather than one apiece.
    def token_working?
      return @token_working unless @token_working.nil?

      @token_working = @client.events_readable?
    end

    # update_columns, not update!: this runs every fifteen minutes per event, and
    # has_paper_trail would write a version for each pass.
    def record_state(event, error:)
      event.update_columns(pretix_sync_error: error,
                           pretix_synced_at: error ? event.pretix_synced_at : Time.current)
    end

    # is_public false means the producer hid the subevent from the shop's
    # listings; it is dropped before matching, so its row is treated as gone.
    #
    # active is NOT filtered on: a date not yet on sale and a date pulled both look
    # like it, and pretix has no cancellation concept, so inferring one would put
    # a wrong CANCELLED on a public page.
    def fetch(event)
      @client.subevents(event.pretix_slug).select { |row| row["is_public"] != false }
    end

    def widen_run(event, subevents)
      dates = subevents.filter_map { |row| parse_time(row["date_from"])&.to_date }
      return if dates.empty?

      start_date = [ event.start_date, dates.min ].compact.min
      end_date = [ event.end_date, dates.max ].compact.max
      return if start_date == event.start_date && end_date == event.end_date

      # Only ever outwards: a run is legitimately wider than its ticketed dates (a
      # get-in, a free preview) but never narrower than a date on sale.
      event.update!(start_date: start_date, end_date: end_date)
    end

    def apply(event, subevents)
      rows = event.event_occurrences.to_a
      existing = rows.select(&:pretix_synced?).index_by(&:pretix_subevent_id)
      # Hand-typed rows an incoming date might BE. Claimed as adopted, so two
      # subevents at one time cannot take the same row.
      unclaimed = rows.reject(&:pretix_synced?).sort_by(&:id)
      counts = Hash.new(0)

      subevents.each { |row| counts[upsert(event, existing, unclaimed, row)] += 1 }

      seen = subevents.filter_map { |row| row["id"] }
      (existing.keys - seen).each { |id| counts[discard(existing.fetch(id))] += 1 }

      Result.new(created: counts[:created], updated: counts[:updated], adopted: counts[:adopted],
                 destroyed: counts[:destroyed], kept: counts[:kept], skipped: counts[:skipped],
                 emptied_series: subevents.empty? && existing.any?, missing_series: false)
    end

    def upsert(event, existing, unclaimed, row)
      occurrence, outcome = match(event, existing, unclaimed, row)

      occurrence.assign_attributes(attributes_from(row))
      occurrence.save!
      outcome
    rescue ActiveRecord::RecordInvalid => e
      # One unreadable date must not take the run down: the other performances are
      # correct and belong on the site today.
      Rails.logger.warn("Pretix performance sync skipped subevent #{row['id']} " \
                        "for #{event.pretix_slug}: #{e.message}")
      :skipped
    end

    # Which row this subevent is, by confidence: the one already carrying its id,
    # then a hand-typed row at exactly the same time, then a new one.
    #
    # The middle case is ADOPTION: it stops a producer who typed their dates before
    # ticking the box getting every night twice, and keeps the flags and note
    # already on the row. A row at a different time is NOT merged: that is a
    # matinee, a preview, or a genuine disagreement, none of them the sync's to
    # resolve.
    def match(event, existing, unclaimed, row)
      claimed = existing[row["id"]]
      return [ claimed, :updated ] if claimed

      starts_at = parse_time(row["date_from"])
      adoptee = starts_at && unclaimed.find { |occurrence| occurrence.starts_at == starts_at }

      if adoptee
        unclaimed.delete(adoptee)
        adoptee.pretix_subevent_id = row["id"]
        return [ adoptee, :adopted ]
      end

      [ event.event_occurrences.build(pretix_subevent_id: row["id"]), :created ]
    end

    # A cancelled row is something a person said to the public, so it outlives its
    # subevent. It keeps its id, so a date restored in pretix reattaches to it
    # instead of arriving as a duplicate.
    def discard(occurrence)
      return :kept if occurrence.cancelled?

      occurrence.destroy!
      :destroyed
    end

    # The only four columns this sync owns; access_flags, note and cancelled are
    # never assigned, on create or update.
    def attributes_from(row)
      { starts_at: parse_time(row["date_from"]),
        ends_at: parse_time(row["date_to"]),
        admission_at: parse_time(row["date_admission"]),
        sold_out: sold_out?(row) }
    end

    def sold_out?(row)
      state = row["best_availability_state"]

      state.present? && state < AVAILABLE_STATE
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    end
  end
end
