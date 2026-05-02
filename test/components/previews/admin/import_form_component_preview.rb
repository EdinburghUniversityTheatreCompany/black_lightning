class Admin::ImportFormComponentPreview < Admin::ApplicationComponentPreview
  # Standard import form layout (user import example)
  def default
    render_with_template
  end

  # Import form with a longer columns description (membership import example)
  def membership
    render_with_template
  end
end
