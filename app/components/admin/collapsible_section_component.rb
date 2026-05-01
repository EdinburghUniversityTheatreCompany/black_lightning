class Admin::CollapsibleSectionComponent < ViewComponent::Base
  def initialize(title:, card_class: "", body_class: "", header_class: "", title_right: nil, start_open: false, flush: false)
    @title = title
    @card_class = card_class
    @body_class = body_class
    @header_class = header_class
    @title_right = title_right
    @start_open = start_open
    @flush = flush
  end
end
