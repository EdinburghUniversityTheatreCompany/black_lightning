class Admin::CardComponentPreview < ViewComponent::Preview
  def default
    render CardComponent.new(title: "Example Card") do
      "<p>Some card content goes here.</p>".html_safe
    end
  end

  def danger_variant
    render CardComponent.new(title: "You are in debt", variant: :danger) do
      "<p>Outstanding debts.</p>".html_safe
    end
  end

  def flush_list
    render CardComponent.new(title: "Resources", flush: true) do
      content_tag(:ul, class: "list-group") do
        ActionController::Base.helpers.safe_join([
          content_tag(:li, class: "list-group-item") { link_to "Wiki", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Minutes", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Membership Checker", "#" }
        ])
      end
    end
  end
end
