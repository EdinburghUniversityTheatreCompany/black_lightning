# frozen_string_literal: true

module Pretix
  ##
  # Brings ONE event's performances in line with its pretix series.
  #
  # A Bedlam show is a pretix event series, so each subevent is one dated
  # performance -- exactly what an EventOccurrence is. The producer enters the
  # dates once, in the shop that actually sells the tickets, instead of twice.
  #
  # The ownership model is the whole design, and it is carried by one column:
  #
  #   pretix_subevent_id set   -> pretix's row. Its times and availability are
  #                               overwritten on every pass, and it is destroyed
  #                               when the subevent goes.
  #   pretix_subevent_id nil   -> typed by hand (a preview, a get-in, a schools
  #                               matinee). Never read, never written, never
  #                               deleted.
  #
  # +access_flags+, +note+ and +cancelled+ are the producer's on BOTH kinds of
  # row and are never written here. That is what lets someone tick the box and
  # still tag the relaxed night.
  #
  # See docs/superpowers/specs/2026-08-31-pretix-performance-sync-design.md.
  class PerformanceSync
    # pretix documents 100 as "tickets available" and anything below it as "sold
    # out or reserved". null means "status unknown" and is deliberately NOT read
    # as sold out -- telling someone they cannot buy a ticket they can is the
    # more costly direction of this error.
    AVAILABLE_STATE = 100


    Result = Data.define(:created, :updated, :adopted, :destroyed, :kept, :skipped,
                         :emptied_series, :missing_series) do
      def emptied_series? = emptied_series

      def missing_series? = missing_series

      def any_change? = created.positive? || updated.positive? || adopted.positive? || destroyed.positive?

      def to_h = { created:, updated:, adopted:, destroyed:, kept:, skipped: }
    end

    # +client+ is a constructor seam, as MembershipSync's is: this suite has no
    # mocking library, so the outbound client is faked and injected.
    # What a pass returns when pretix has no such series yet: nothing was read,
    # so nothing changed. Built after Result is defined.
    MISSING_SERIES = Result.new(created: 0, updated: 0, adopted: 0, destroyed: 0, kept: 0,
                                skipped: 0, emptied_series: false, missing_series: true).freeze

    def initialize(client: Client.new)
      @client = client
    end

    ##
    # Fetches first and mutates second, deliberately: a 404, an auth failure or a
    # timeout raises out of here before a single row has been touched, so a
    # pretix outage leaves the run standing rather than blanking it. The caller
    # (Pretix::SyncPerformancesJob) turns that into a report.
    ##
    def call(event)
      subevents = fetch(event)

      # The run dates and the performance list state the same fact twice, and
      # EventOccurrence#starts_at_within_run refuses to let them contradict each
      # other. Widening BEFORE saving is what lets a date pretix is selling
      # beyond the entered run save at all.
      widen_run(event, subevents)

      result = apply(event, subevents)
      record_state(event, error: nil)
      result
    rescue Client::NotFoundError
      # NOT a failure. Ticking the box before building the ticket shop is the
      # natural order to work in, so this is a waiting state: it is recorded for
      # the admin page to show, existing performances stand untouched, and
      # nothing is raised -- otherwise every such event would alert every
      # fifteen minutes for the length of its run.
      record_state(event, error: "No pretix ticket shop found for \"#{event.pretix_slug}\" yet. " \
                                 "The dates will sync as soon as one exists.")
      MISSING_SERIES
    end

    private

    # update_columns, not update!: this runs every fifteen minutes per event, and
    # has_paper_trail would otherwise write a version for each pass. It is
    # bookkeeping about the sync, not a change to the event.
    def record_state(event, error:)
      event.update_columns(pretix_sync_error: error,
                           pretix_synced_at: error ? event.pretix_synced_at : Time.current)
    end

    # is_public is false for a subevent the producer has hidden from the shop's
    # listings. Hidden there means hidden here, so it is dropped before matching
    # and its row is then treated as gone.
    #
    # active is NOT filtered on: it means the shop is closed for that date, which
    # a date not yet on sale and a date pulled both look like. pretix has no
    # cancellation concept at all, so inferring one is what would put a wrong
    # CANCELLED on a public page.
    def fetch(event)
      @client.subevents(event.pretix_slug).select { |row| row["is_public"] != false }
    end

    def widen_run(event, subevents)
      dates = subevents.filter_map { |row| parse_time(row["date_from"])&.to_date }
      return if dates.empty?

      start_date = [ event.start_date, dates.min ].compact.min
      end_date = [ event.end_date, dates.max ].compact.max
      return if start_date == event.start_date && end_date == event.end_date

      # Only ever outwards. A run is legitimately wider than its ticketed dates
      # -- a get-in, a free preview -- but never narrower than a date on sale.
      event.update!(start_date: start_date, end_date: end_date)
    end

    def apply(event, subevents)
      rows = event.event_occurrences.to_a
      existing = rows.select(&:pretix_synced?).index_by(&:pretix_subevent_id)
      # Hand-typed rows an incoming date might turn out to BE. Claimed as they
      # are adopted, so two subevents at one time cannot both take the same row.
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
      # One unreadable date must not take the rest of the run down with it: the
      # other performances are correct and belong on the site today.
      Rails.logger.warn("Pretix performance sync skipped subevent #{row['id']} " \
                        "for #{event.pretix_slug}: #{e.message}")
      :skipped
    end

    ##
    # Which row this subevent is, in order of confidence: the one already
    # carrying its id, then a hand-typed row at exactly the same time, then a new
    # one.
    #
    # The middle case is ADOPTION, and it is what stops a producer who typed
    # their dates in before ticking the box getting every night twice. Same
    # curtain time means same performance, so the existing row is taken over --
    # keeping the access flags and note already on it -- rather than a second
    # row appearing beside it. A row at a different time is deliberately NOT
    # merged: that is a matinee, a preview, or a genuine disagreement, and none
    # of those are the sync's to resolve.
    ##
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

    # A cancelled row is the one thing here a person said to the public, so it
    # outlives its subevent. It keeps its id, so a date restored in pretix
    # reattaches to this row instead of arriving as a duplicate.
    def discard(occurrence)
      return :kept if occurrence.cancelled?

      occurrence.destroy!
      :destroyed
    end

    # The only four columns this sync owns. Everything else on the row --
    # access_flags, note, cancelled -- is the producer's and is never assigned
    # here, on create or on update.
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
