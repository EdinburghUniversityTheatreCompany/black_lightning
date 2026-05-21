class BadgeComponent < ViewComponent::Base
  STYLES = {
    primary:   "bg-primary text-white",
    success:   "bg-success/15 text-success",
    danger:    "bg-danger/15 text-danger",
    warning:   "bg-warning/15 text-warning",
    info:      "bg-info/15 text-info",
    secondary: "bg-gray-100 text-gray-700",
    dark:      "bg-gray-700 text-white",
    light:     "bg-gray-100 text-gray-800"
  }.freeze

  def initialize(type: :secondary, pill: false, pull_right: false, html_class: nil)
    @type = type.to_sym
    @pill = pill
    @pull_right = pull_right
    @html_class = html_class
  end

  def style_classes
    base = STYLES.fetch(@type, STYLES[:secondary])
    base += " rounded-full" if @pill
    base += " float-right" if @pull_right
    base += " #{@html_class}" if @html_class
    base
  end
end
