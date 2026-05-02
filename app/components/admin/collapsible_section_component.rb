class Admin::CollapsibleSectionComponent < ViewComponent::Base
  def initialize(title:, variant: :default, flush: false, start_open: false, title_right: nil, html_class: "")
    @title = title
    @variant = variant.to_sym
    @flush = flush
    @start_open = start_open
    @title_right = title_right
    @html_class = html_class
  end

  def header_classes
    Admin::CardComponent::HEADER_VARIANTS.fetch(@variant, Admin::CardComponent::HEADER_VARIANTS[:default])
  end
end
