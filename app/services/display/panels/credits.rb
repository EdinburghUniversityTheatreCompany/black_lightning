module Display
  module Panels
    class Credits
      def initialize(on: Date.current)
        @on = on
      end

      def available?
        event.present? && members.any?
      end

      def partial
        "display/panels/credits"
      end

      def locals
        cast, crew = members.partition(&:cast?)

        { event: event, cast: cast, crew: crew, tonight: event.on_today?(@on) }
      end

      private

      # The pool sorts tonight's shows first, so slot 1 is tonight's or the next one.
      def event
        return @event if defined?(@event)

        @event = Display::EventPool.slot(1, on: @on)
      end

      # preload, not includes: TeamMember.ordered already joins users.
      def members
        @members ||= event.team_members.ordered.preload(:user).to_a
      end
    end
  end
end
