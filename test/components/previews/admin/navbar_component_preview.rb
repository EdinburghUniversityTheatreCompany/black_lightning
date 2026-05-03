class Admin::NavbarComponentPreview < Admin::ApplicationComponentPreview
  def default
    render Admin::NavbarComponent.new(current_user: sample_user, title: "Example Page")
  end

  def with_badges
    render Admin::NavbarComponent.new(
      current_user: sample_user,
      title: "Example Page",
      header_badges: [
        { label_class: "bg-success text-white", text: "Active" },
        { label_class: "bg-secondary text-white", text: "Draft" }
      ]
    )
  end
end
