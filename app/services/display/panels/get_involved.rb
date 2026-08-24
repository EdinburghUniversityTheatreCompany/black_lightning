module Display
  module Panels
    class GetInvolved < Base
      LIMIT = 5

      def available?
        opportunities.any?
      end

      def partial
        "display/panels/get_involved"
      end

      def locals
        { opportunities: opportunities }
      end

      private

      def opportunities
        @opportunities ||= Opportunity.active.includes(:company, :roles).limit(LIMIT).to_a
      end
    end
  end
end
