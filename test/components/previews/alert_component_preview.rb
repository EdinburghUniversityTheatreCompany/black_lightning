class AlertComponentPreview < ViewComponent::Preview
  def danger
    render AlertComponent.new(type: :danger) do
      "Something went wrong. Please try again."
    end
  end

  def success
    render AlertComponent.new(type: :success) do
      "Changes saved successfully."
    end
  end

  def warning
    render AlertComponent.new(type: :warning) do
      "Please review this before continuing."
    end
  end

  def info
    render AlertComponent.new(type: :info) do
      "Here is some useful information."
    end
  end
end
