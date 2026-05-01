class Admin::CollapsibleSectionComponentPreview < Admin::ApplicationComponentPreview
  def default
    render Admin::CollapsibleSectionComponent.new(title: "Example Section") do
      "<p class='text-sm text-gray-700'>Collapsible content goes here.</p>".html_safe
    end
  end

  def start_open
    render Admin::CollapsibleSectionComponent.new(title: "Open by Default", start_open: true) do
      "<p class='text-sm text-gray-700'>This section starts expanded.</p>".html_safe
    end
  end
end
