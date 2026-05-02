class Admin::CardComponent < ViewComponent::Base
  HEADER_VARIANTS = {
    default: "bg-gray-50 text-gray-700 border-gray-200",
    danger:  "bg-red-600 text-white border-red-600",
    success: "bg-green-600 text-white border-green-600",
    warning: "bg-yellow-500 text-white border-yellow-500",
    info:    "bg-blue-500 text-white border-blue-500",
    primary: "bg-primary text-white border-primary"
  }.freeze

  def initialize(title:, variant: :default, flush: false, html_class: "")
    @title = title
    @variant = variant.to_sym
    @flush = flush
    @html_class = html_class
  end

  def header_classes
    HEADER_VARIANTS.fetch(@variant, HEADER_VARIANTS[:default])
  end
end
