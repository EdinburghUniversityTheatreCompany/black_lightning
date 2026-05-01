class Admin::CardWidgetComponent < ViewComponent::Base
  def initialize(title:, card_class: "", start_open: true, flush: false)
    @title = title
    @card_class = card_class
    @start_open = start_open
    @flush = flush
  end
end
