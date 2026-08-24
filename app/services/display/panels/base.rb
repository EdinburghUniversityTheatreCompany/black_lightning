module Display
  module Panels
    # A panel answers three questions: does it have anything to show, which
    # partial draws it, and what does that partial need.
    class Base
      def available?
        raise NotImplementedError
      end

      def partial
        raise NotImplementedError
      end

      def locals
        {}
      end
    end
  end
end
