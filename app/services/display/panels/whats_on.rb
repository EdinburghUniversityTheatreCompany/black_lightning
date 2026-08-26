module Display
  module Panels
    class WhatsOn < Base
      # More events than fit on the frame at once. The board scrolls the
      # overflow past (see .display-marquee in display.css), so the cap is about
      # how long a pass takes to read rather than about the height of a screen
      # -- during the Fringe the pool is far longer than this.
      ROWS = 12

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
        { events: events, on: @on }
      end

      private

      def events
        @events ||= Display::EventPool.upcoming(on: @on).first(ROWS)
      end
    end
  end
end
