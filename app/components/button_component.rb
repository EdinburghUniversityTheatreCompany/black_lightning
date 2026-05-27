class ButtonComponent < ViewComponent::Base
  BASE_CLASSES = "btn inline-flex items-center gap-1.5 px-3 py-1.5 rounded text-sm font-medium cursor-pointer no-underline transition-colors".freeze

  VARIANT_CLASSES = {
    primary:   "bg-white border border-primary text-primary hover:bg-primary hover:text-white",
    secondary: "bg-white border border-slate-400 text-slate-600 hover:bg-slate-50",
    danger:    "bg-danger text-white hover:bg-danger/80",
    success:   "bg-success text-white hover:bg-success/80",
    warning:   "bg-warning text-white hover:bg-warning/80",
    info:      "bg-info text-white hover:bg-info/80",
    link:      "bg-transparent border-0 text-primary underline hover:text-primary-dark px-0"
  }.freeze

  SIZE_CLASSES = {
    sm: "text-xs px-2 py-1",
    md: "",
    lg: "text-base px-4 py-2"
  }.freeze

  def self.classes_for(variant: :secondary, size: :md)
    [
      BASE_CLASSES,
      VARIANT_CLASSES.fetch(variant, VARIANT_CLASSES[:secondary]),
      SIZE_CLASSES.fetch(size, "")
    ].join(" ").strip
  end

  def initialize(href: nil, variant: :secondary, size: :md, disabled: false, type: "button", **html_options)
    @href = href
    @variant = variant.to_sym
    @size = size.to_sym
    @disabled = disabled
    @type = type
    @html_options = html_options
  end

  def button_classes
    self.class.classes_for(variant: @variant, size: @size)
  end
end
