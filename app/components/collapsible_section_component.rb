class CollapsibleSectionComponent < ViewComponent::Base
  def initialize(title:, variant: :default, flush: false, start_open: false, html_class: "")
    @title = title
    @variant = variant.to_sym
    @flush = flush
    @start_open = start_open
    @html_class = html_class
  end

  def header_classes
    CardComponent::HEADER_VARIANTS.fetch(@variant, CardComponent::HEADER_VARIANTS[:default])
  end
end
