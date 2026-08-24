module Display
  module Panels
    # One slot of the rotation. Slots wrap, so six slots against four events
    # repeat the first two rather than leaving a dark screen.
    class NextEvent < Base
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
