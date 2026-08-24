module Display
  module Panels
    # Something from the archive that ran on today's date in an earlier year.
    #
    # Event.on_date matches on month and day only, and its own comment records
    # that it deliberately skips runs crossing the new year (the Imps,
    # Candlewasters). Bedlam does not programme across the new year, so that gap
    # costs nothing and is cheaper than a second scope kept in step with it.
    class OnThisDay < Base
      MAX_RUN_DAYS = 60

      def initialize(on: Date.current)
        @on = on
      end

      def available?
        event.present?
      end

      def partial
        "display/panels/on_this_day"
      end

      def locals
        { event: event, years_ago: @on.year - event.start_date.year }
      end

      private

      def event
        return @event if defined?(@event)

        @event = Event.on_date(@on)
                      .where(is_public: true)
                      .where("end_date < ?", @on - 1.year)
                      .where("DATEDIFF(end_date, start_date) <= ?", MAX_RUN_DAYS)
                      # fetch_image attaches a generated placeholder, so "has
                      # artwork" has to be asked of the database, before anything
                      # calls it.
                      .joins(:image_attachment)
                      # reorder, not order: Event's default_scope is end_date DESC,
                      # so order would append and "oldest" would mean something else.
                      .reorder(:start_date)
                      .first
      end
    end
  end
end
