module Display
  module Panels
    class WhatsOn < Base
      ROWS = 8

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
