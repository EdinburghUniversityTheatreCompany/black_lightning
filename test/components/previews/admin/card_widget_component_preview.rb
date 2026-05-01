class Admin::CardWidgetComponentPreview < Admin::ApplicationComponentPreview
  def default
    render Admin::CardWidgetComponent.new(title: "Example Widget") do
      "<p>Some widget content goes here.</p>".html_safe
    end
  end

  def with_link_title
    render Admin::CardWidgetComponent.new(title: "<a href='#'>Upcoming Shows</a>".html_safe) do
      "<p><a href='#'>Odyssey</a></p><p><a href='#'>Test Show</a></p>".html_safe
    end
  end

  def card_danger
    render Admin::CardWidgetComponent.new(title: "You are in debt", card_class: "card-danger") do
      "<p>You have outstanding debts.</p>".html_safe
    end
  end

  def card_success
    render Admin::CardWidgetComponent.new(title: "You are not in debt", card_class: "card-success") do
      "<p>No outstanding debts.</p>".html_safe
    end
  end

  def start_closed
    render Admin::CardWidgetComponent.new(title: "Collapsed by Default", start_open: false) do
      "<p>This content starts hidden.</p>".html_safe
    end
  end

  def flush_list
    render Admin::CardWidgetComponent.new(title: "Resources", flush: true) do
      content_tag(:ul, class: "list-group list-group-flush") do
        [
          content_tag(:li, class: "list-group-item") { link_to "Wiki", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Minutes", "#" },
          content_tag(:li, class: "list-group-item") { link_to "Membership Checker", "#" }
        ].join.html_safe
      end
    end
  end
end
