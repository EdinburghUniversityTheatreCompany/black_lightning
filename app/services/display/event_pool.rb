module Display
  # The single ordered list of events behind the slot pages, the What's On board
  # and the credits page.
  #
  # There is deliberately NO type filter and no duration rule. A Season is
  # normally a festival -- exactly what the box office should be advertising --
  # not a term-long container, and the only lever for an unusually long run is
  # performance_weekdays. A duration rule here would also drop a three-week
  # Fringe run, which genuinely is on every night.
  #
  # Ordering happens in Ruby rather than SQL: the pool is a handful of rows and
  # the weekday logic does not belong in a query.
  class EventPool
    # Not Event.current -- that scope hardcodes Date.current, so it would ignore
    # the +on+ argument the ordering is tested with.
    def self.upcoming(on: Date.current)
      Event.where(is_public: true)
           .where("end_date >= ?", on)
           .includes(image_attachment: :blob)
           .to_a
           .select { |event| event.next_occurrence(on).present? }
           # start_date and id are tiebreakers, not decoration: sort_by is not
           # stable and every event running today shares [0, today], so without a
           # total order the six slot pages -- fetched minutes apart, each
           # re-sorting independently -- can show the same show twice and skip
           # another. During the Fringe that is the normal state.
           .sort_by { |event| [ event.on_today?(on) ? 0 : 1, event.next_occurrence(on), event.start_date, event.id ] }
    end

    # Slot numbers are 1-based and wrap: six slots against four events shows
    # events 1, 2, 3, 4, 1, 2. Repeating a poster beats a dark screen.
    def self.slot(number, on: Date.current)
      pool = upcoming(on: on)
      return nil if pool.empty?

      pool[(number - 1) % pool.size]
    end
  end
end
