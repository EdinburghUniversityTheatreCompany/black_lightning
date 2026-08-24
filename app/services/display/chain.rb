module Display
  # An ordered list of panels; the first that reports content is what renders.
  #
  # Chain appends Panels::Identity itself. Identity runs no query and is
  # therefore always available, so resolve cannot come back empty and a URL in
  # the Anthias playlist cannot render blank -- and no caller has to remember to
  # terminate its own chain for that to hold.
  class Chain
    # Unreachable by construction; kept so a future change that breaks the
    # terminal-panel invariant fails loudly rather than returning nil.
    class NoPanelAvailableError < StandardError; end

    def initialize(*panels)
      @panels = panels + [ Display::Panels::Identity.new ]
    end

    def resolve
      @panels.find(&:available?) ||
        raise(NoPanelAvailableError, "no panel reported content; every chain must end in Panels::Identity")
    end
  end
end
