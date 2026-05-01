class Admin::PageHeaderComponentPreview < ViewComponent::Preview
  def default
    render Admin::PageHeaderComponent.new(title: "Example Page")
  end

  def with_badges
    render Admin::PageHeaderComponent.new(
      title: "Example Page",
      header_badges: [
        { label_class: "bg-success text-white", text: "Active" },
        { label_class: "bg-secondary text-white", text: "Draft" }
      ]
    )
  end
end
