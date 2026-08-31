# frozen_string_literal: true

module Pretix
  ##
  # Switches performance sync on across every future event that can take it.
  #
  # No probe: an event whose ticket shop does not exist yet simply waits, showing
  # a warning on its admin page (see PerformanceSync's NotFoundError handling),
  # and an event whose producer already typed the dates has those rows ADOPTED by
  # the matching subevents rather than duplicated. Both of the reasons this used
  # to ask pretix first are now handled by the sync itself.
  #
  # Dry by default, following Event::TicketPriceBackfill.
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

    # Bounded by the run's end, as the job itself is: a finished run has nothing
    # left to sell.
    def candidates
      Event.where(end_date: Date.current..).order(:start_date)
    end

    def classify(event, apply:)
      # A Season's occurrences are opening times, not performances. Filling them
      # from ticketed dates would claim the theatre is staging a show on every
      # day the box office happens to be open.
      return :not_performances unless event.occurrences_are_performances?
      return :already_on if event.pretix_sync_performances?

      event.update!(pretix_sync_performances: true) if apply
      :enabled
    end
  end
end
