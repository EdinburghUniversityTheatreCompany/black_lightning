class AlertComponent < ViewComponent::Base
  STYLES = {
    danger:  "bg-danger/10 border-danger/30 text-danger",
    warning: "bg-warning/10 border-warning/30 text-warning",
    success: "bg-success/10 border-success/30 text-success",
    info:    "bg-info/10 border-info/30 text-info"
  }.freeze

  def initialize(type: :info, html_class: nil)
    @type = type.to_sym
    @html_class = html_class
  end

  def style_classes
    STYLES.fetch(@type, STYLES[:info])
  end
end
