module Display
  # The ordered list of events behind the slot pages, the What's On board and the
  # credits page. No type filter and no duration rule: a Season is normally a
  # festival the box office should advertise, and a duration rule would drop a
  # three-week Fringe run that is on every night. Ordering is in Ruby because the
  # pool is a handful of rows and next_occurrence reads a preloaded association.
  class EventPool
    # The RUN DATES decide what is on, not the performance list: a producer who
    # enters the first week's performances and forgets the second would otherwise
    # see the show vanish for week two. Such an event stays until its end_date.
    # Not Event.current: it hardcodes Date.current and would ignore +on+.
    def self.upcoming(on: Date.current)
      Event.where(is_public: true)
           .where("end_date >= ?", on)
           .includes(:event_occurrences, image_attachment: :blob)
           .to_a
           # start_date and id make the order total: sort_by is not stable and every
           # event running today shares [0, today], so six slot pages fetched minutes
           # apart could show the same show twice and skip another (the Fringe norm).
           # next_occurrence is nil once the listed performances have passed but the
           # run has not; end_date stands in.
           .sort_by { |event| [ event.on_today?(on) ? 0 : 1, event.next_occurrence(on) || event.end_date, event.start_date, event.id ] }
    end

    # Slot numbers are 1-based and wrap (six slots, four events: 1, 2, 3, 4, 1, 2).
    # Repeating a poster beats a dark screen.
    def self.slot(number, on: Date.current)
      pool = upcoming(on: on)
      return nil if pool.empty?

      pool[(number - 1) % pool.size]
    end
  end
end
