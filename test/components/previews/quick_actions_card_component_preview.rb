class QuickActionsCardComponentPreview < ViewComponent::Preview
  def default
    render QuickActionsCardComponent.new do
      helpers.link_to("Edit", "#", class: ButtonComponent.classes_for(variant: :primary)) +
        helpers.link_to("All News", "#", class: ButtonComponent.classes_for(variant: :secondary))
    end
  end

  def single_action
    render QuickActionsCardComponent.new do
      helpers.link_to("Back", "#", class: ButtonComponent.classes_for(variant: :secondary))
    end
  end
end
