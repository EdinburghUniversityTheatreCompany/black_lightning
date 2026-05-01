class Admin::CardWidgetComponent < ViewComponent::Base
  def initialize(title:, card_class: "", start_open: true)
    @title = title
    @card_class = card_class
    @start_open = start_open
  end
end
