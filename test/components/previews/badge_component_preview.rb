class BadgeComponentPreview < ViewComponent::Preview
  def danger
    render BadgeComponent.new(type: :danger) { "Unpaid" }
  end

  def success
    render BadgeComponent.new(type: :success) { "Member" }
  end

  def warning
    render BadgeComponent.new(type: :warning) { "Pending" }
  end

  def info
    render BadgeComponent.new(type: :info) { "EUTC Member" }
  end

  def secondary
    render BadgeComponent.new(type: :secondary) { "Non-Member" }
  end

  def primary
    render BadgeComponent.new(type: :primary) { "Target" }
  end

  def pill
    render BadgeComponent.new(type: :primary, pill: true) { "42" }
  end

  def dark
    render BadgeComponent.new(type: :dark) { "Count: 5" }
  end
end
