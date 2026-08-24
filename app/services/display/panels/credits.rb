module Display
  module Panels
    class Credits < Base
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

      def event
        return @event if defined?(@event)

        @event = pool.find { |candidate| candidate.on_today?(@on) } || pool.first
      end

      # preload rather than includes: TeamMember.ordered already joins users to
      # order by them, and preload fetches the records without fighting it.
      def members
        @members ||= event ? event.team_members.ordered.preload(:user).to_a : []
      end
    end
  end
end
