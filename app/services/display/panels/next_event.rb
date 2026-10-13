module Display
  module Panels
    # One slot of the EventPool rotation (slots wrap).
    class NextEvent
      def initialize(slot, on: Date.current)
        @slot = slot
        @on = on
      end

      def available?
        event.present?
      end

      def partial
        "display/panels/next_event"
      end

      def locals
        { event: event, tonight: event.on_today?(@on), on: @on }
      end

      private

      def event
        return @event if defined?(@event)

        @event = Display::EventPool.slot(@slot, on: @on)
      end
    end
  end
end
