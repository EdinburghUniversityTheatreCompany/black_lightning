module Display
  module Panels
    class WhatsOn
      # More than fits the frame: the board scrolls the overflow (.display-marquee in
      # display.css), so this caps how long a pass takes, not the screen height.
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
