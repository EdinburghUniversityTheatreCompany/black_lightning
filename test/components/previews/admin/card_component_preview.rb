class Admin::CardComponentPreview < Admin::ApplicationComponentPreview
  def default
    render Admin::CardComponent.new(title: "Example Card") do
      "<p>Some card content goes here.</p>".html_safe
    end
  end

  def with_link_title
    render Admin::CardComponent.new(title: "<a href='#'>Upcoming Shows</a>".html_safe) do
      "<p><a href='#'>Odyssey</a></p><p><a href='#'>Test Show</a></p>".html_safe
    end
  end

  def danger_variant
    render Admin::CardComponent.new(title: "You are in debt", variant: :danger) do
      "<p>You have outstanding debts.</p>".html_safe
    end
  end

  def success_variant
    render Admin::CardComponent.new(title: "You are not in debt", variant: :success) do
      "<p>No outstanding debts.</p>".html_safe
    end
  end

  def flush_list
    render Admin::CardComponent.new(title: "Resources", flush: true) do
      content_tag(:ul, class: "list-group") do
        [
          content_tag(:li, class: "list-group-item") { link_to "Wiki", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Minutes", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Membership Checker", "#" }
        ].join.html_safe
      end
    end
  end
end
