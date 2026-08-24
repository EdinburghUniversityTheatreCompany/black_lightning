module Display
  # An ordered list of panels; the first that reports content is what renders.
  #
  # Every chain must end with Panels::Identity, which runs no query and is
  # therefore always available. That is what makes it impossible for a URL in
  # the Anthias playlist to render blank.
  class Chain
    class NoPanelAvailableError < StandardError; end

    def initialize(*panels)
      @panels = panels
    end

    def resolve
      @panels.find(&:available?) ||
        raise(NoPanelAvailableError, "no panel reported content; every chain must end in Panels::Identity")
    end
  end
end
