# frozen_string_literal: true

module Pretix
  # Switches performance sync on across every future event that can take it.
  # Dry by default, following Event::TicketPriceBackfill.
  #
  # No probe of pretix: an event with no shop yet waits with a warning on its
  # admin page, and dates already typed are ADOPTED by the matching subevents.
  class PerformanceSyncEnablement
    Summary = Data.define(:enabled, :already_on, :not_performances) do
      def considered
        [ enabled, already_on, not_performances ].sum(&:length)
      end
    end

    def call(apply:)
      buckets = Hash.new { |hash, key| hash[key] = [] }

      candidates.each { |event| buckets[classify(event, apply: apply)] << event }

      Summary.new(enabled: buckets[:enabled], already_on: buckets[:already_on],
                  not_performances: buckets[:not_performances])
    end

    private

    # Bounded by the run's end, as the job is.
    def candidates
      Event.where(end_date: Date.current..).order(:start_date)
    end

    def classify(event, apply:)
      # A Season's occurrences are opening times, not performances: filling them
      # from ticketed dates would claim a show on every day the box office is open.
      return :not_performances unless event.occurrences_are_performances?
      return :already_on if event.pretix_sync_performances?

      event.update!(pretix_sync_performances: true) if apply
      :enabled
    end
  end
end
