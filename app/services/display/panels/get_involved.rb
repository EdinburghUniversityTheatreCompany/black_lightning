module Display
  module Panels
    class GetInvolved
      # The list scrolls in a fixed-length pass, so more items scroll faster. At 158px
      # an item (one with roles), ten overflow the 680px window by 900px at most,
      # inside What's On's worst case (~1030px): never a faster scroll than that board's.
      LIMIT = 10

      # The website's own empty-state copy, so it is edited in one place.
      EMPTY_STATE_BLOCK = "No Opportunities".freeze

      def available?
        opportunities.any? || empty_state_copy?
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

      # Without the block, display_block prints "Block not defined" on the wall.
      # Report unavailable instead so the chain falls through.
      def empty_state_copy?
        Admin::EditableBlock.exists?(name: EMPTY_STATE_BLOCK)
      end
    end
  end
end
