class Admin::EventsGridComponent < ViewComponent::Base
  def initialize(items:, col_size: 12, link_to_admin_events: false)
    @items = items
    @col_size = col_size
    @link_to_admin_events = link_to_admin_events
  end

  def grid_classes
    amount = @items.size

    if @col_size == 8
      # 4 items: prefer 2×2 over 3+1
      display_amount = amount == 4 ? 2 : amount
      case display_amount
      when 1    then "grid grid-cols-1 gap-4"
      when 2    then "grid grid-cols-1 md:grid-cols-2 gap-4"
      else           "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
      end
    else
      case amount
      when 1    then "grid grid-cols-1 lg:grid-cols-2 gap-4"
      when 2    then "grid grid-cols-1 sm:grid-cols-2 gap-4"
      when 3    then "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4"
      else           "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4"
      end
    end
  end

  def url_for_item(item)
    @link_to_admin_events ? [ :admin, item[:event] ] : item[:event]
  end
end
