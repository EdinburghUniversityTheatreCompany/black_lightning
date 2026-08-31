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

      # A date in the middle of the Fringe matches dozens of archive shows, and
      # the screen comes back to this URL every few minutes: Display::Rotation
      # moves on one place per render so it is a different show each time rather
      # than the oldest one all day.
      def event
        return @event if defined?(@event)

        @event = rotate_to_next
      end

      def rotate_to_next
        ids = candidate_ids
        return nil if ids.empty?

        index = Display::Rotation.next_index("on-this-day", size: ids.size, on: @on)

        # ids first, so only the event actually going on screen is loaded.
        Event.includes(image_attachment: :blob).find_by(id: ids[index])
      end

      def candidate_ids
        Event.on_date(@on)
             .where(is_public: true)
             .where("end_date < ?", @on - 1.year)
             .where("DATEDIFF(end_date, start_date) <= ?", MAX_RUN_DAYS)
             # fetch_image attaches a generated placeholder, so "has artwork" has
             # to be asked of the database, before anything calls it -- and asked
             # of the blob's filename, since the placeholder is an attachment too.
             .with_uploaded_image
             # reorder, not order: Event's default_scope is end_date DESC, so
             # order would append and "oldest" would mean something else. id
             # breaks ties, because the rotation walks this list by position and
             # two shows opening on the same date would otherwise be free to swap
             # places between renders -- showing one twice and skipping the other.
             .reorder(:start_date, :id)
             .pluck(:id)
      end
    end
  end
end
