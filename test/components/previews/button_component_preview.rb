class ButtonComponentPreview < ViewComponent::Preview
  def primary
    render ButtonComponent.new(href: "#", variant: :primary).with_content("New Thing")
  end

  def secondary
    render ButtonComponent.new(href: "#", variant: :secondary).with_content("Cancel")
  end

  def danger
    render ButtonComponent.new(href: "#", variant: :danger).with_content("Delete")
  end

  def success
    render ButtonComponent.new(href: "#", variant: :success).with_content("Confirm")
  end

  def warning
    render ButtonComponent.new(href: "#", variant: :warning).with_content("Warning action")
  end

  def info
    render ButtonComponent.new(href: "#", variant: :info).with_content("Info action")
  end

  def link_variant
    render ButtonComponent.new(href: "#", variant: :link).with_content("Link style")
  end

  def small
    render ButtonComponent.new(href: "#", variant: :secondary, size: :sm).with_content("Small")
  end

  def large
    render ButtonComponent.new(href: "#", variant: :primary, size: :lg).with_content("Large")
  end

  def as_button
    render ButtonComponent.new(variant: :primary).with_content("Submit")
  end

  def disabled
    render ButtonComponent.new(variant: :secondary, disabled: true).with_content("Disabled")
  end
end
