class CardComponentPreview < ViewComponent::Preview
  def default
    render CardComponent.new(title: "Example Card") do
      "<p>Some card content goes here.</p>".html_safe
    end
  end

  def without_title
    render CardComponent.new do
      "<p>A card without a header.</p>".html_safe
    end
  end

  def with_footer
    render CardComponent.new(title: "News") do |c|
      c.with_footer { ActionController::Base.helpers.link_to("Read all →", "#") }
      "<p>News content goes here.</p>".html_safe
    end
  end

  def with_tools
    render CardComponent.new(title: "Staffing Grid") do |c|
      c.with_tools { ActionController::Base.helpers.link_to("View All", "#", class: ButtonComponent.classes_for(variant: :secondary, size: :sm)) }
      "<p>Table would go here.</p>".html_safe
    end
  end

  def danger_variant
    render CardComponent.new(title: "You are in debt", variant: :danger) do
      "<p>Outstanding debts.</p>".html_safe
    end
  end

  def flush_list
    render CardComponent.new(title: "Items", flush: true) do
      ActionController::Base.helpers.content_tag(:ul, class: "divide-y") do
        ActionController::Base.helpers.safe_join([
          ActionController::Base.helpers.content_tag(:li, "Item 1", class: "px-4 py-2"),
          ActionController::Base.helpers.content_tag(:li, "Item 2", class: "px-4 py-2")
        ])
      end
    end
  end
end
