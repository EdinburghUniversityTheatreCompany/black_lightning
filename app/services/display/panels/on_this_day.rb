module Display
  module Panels
    # Something from the archive that ran on today's date in an earlier year.
    # Event.on_date matches month and day only and skips runs crossing the new
    # year, which Bedlam does not programme.
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

      # A mid-Fringe date matches dozens of archive shows and the screen returns
      # every few minutes: Rotation moves on one place per render, so it is a
      # different show each time.
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
             # Filters on the blob's filename: fetch_image attaches a placeholder too.
             .with_uploaded_image
             # reorder, not order: Event's default_scope is end_date DESC. id breaks
             # ties because Rotation walks this list by position, and two shows
             # opening on the same date could swap places between renders.
             .reorder(:start_date, :id)
             .pluck(:id)
      end
    end
  end
end
