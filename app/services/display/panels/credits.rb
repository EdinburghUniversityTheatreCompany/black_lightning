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

      def pool
        @pool ||= Display::EventPool.upcoming(on: @on)
      end

      # The pool sorts events running today first, so find and first agree.
      def event
        return @event if defined?(@event)

        @event = pool.find { |candidate| candidate.on_today?(@on) } || pool.first
      end

      # preload, not includes: TeamMember.ordered already joins users.
      def members
        @members ||= event ? event.team_members.ordered.preload(:user).to_a : []
      end
    end
  end
end
