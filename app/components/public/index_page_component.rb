class Public::IndexPageComponent < ViewComponent::Base
  renders_one :search_form

  def initialize(title:, editable_block_name:, resources:, items:)
    @title = title
    @editable_block_name = editable_block_name
    @resources = resources
    @items = items
  end

  private

  def any_items?
    @items.any?
  end
end
