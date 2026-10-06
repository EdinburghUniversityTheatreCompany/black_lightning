module Display
  module Panels
    # The fallback when no other panel has content. It runs no query, so it cannot fail.
    class Identity
      def partial = "display/panels/identity"

      def locals = {}
    end
  end
end
