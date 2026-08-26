module Display
  module Panels
    class WhatsOn < Base
      # More events than fit on the frame at once. The board scrolls the
      # overflow past (see .display-marquee in display.css), so the cap is about
      # how long a pass takes to read rather than about the height of a screen
      # -- during the Fringe the pool is far longer than this.
      ROWS = 12

      # A pass holds at the top, scrolls, and holds at the bottom. The scroll
      # itself only covers the overflow, so seconds-per-event paces the pass
      # rather than setting a true constant speed -- close enough for a board,
      # and it keeps a three-event list from crawling.
      #
      # Whatever this yields for a full board is what the Anthias playlist entry
      # has to be set to, or the tail of the list is never on screen. See
      # Display::SetupController::PAGES.
      HOLD_SECONDS = 4
      SECONDS_PER_EVENT = 1.8

      def self.max_scroll_seconds
        (HOLD_SECONDS + (ROWS * SECONDS_PER_EVENT)).ceil
      end

      def initialize(on: Date.current)
        @on = on
      end

      def available?
        events.any?
      end

      def partial
        "display/panels/whats_on"
      end

      def locals
        { events: events, on: @on, scroll_seconds: scroll_seconds }
      end

      private

      def scroll_seconds
        (HOLD_SECONDS + (events.size * SECONDS_PER_EVENT)).ceil
      end

      def events
        @events ||= Display::EventPool.upcoming(on: @on).first(ROWS)
      end
    end
  end
end
