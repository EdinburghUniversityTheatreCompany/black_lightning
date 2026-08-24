module Display
  module Panels
    # The terminal panel in every chain. It runs no query, so it cannot fail
    # and is always available.
    class Identity < Base
      def available?
        true
      end

      def partial
        "display/panels/identity"
      end
    end
  end
end
