class Admin::ImportPreviewComponentPreview < Admin::ApplicationComponentPreview
  # A crew import's frame; its sections go in the block.
  def default
    render Admin::ImportPreviewComponent.new(total: 3, cancel_path: "#", confirm_path: "#", cache_key: "preview", event_name: "The Tempest") do
      "<p>The import's sections go here.</p>".html_safe
    end
  end
end
