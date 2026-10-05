class EventsGridComponent < ViewComponent::Base
  # The grid of event cards on the home page, a venue and a member's profile.
  # Posters are cropped to one ratio so a row lines up; srcset still spares a
  # phone the 960px poster.
  POSTER_ASPECT = "aspect-[576/300]".freeze

  def initialize(items:, col_size:, link_to_admin_events: false)
    @items = items
    @col_size = col_size
    @link_to_admin_events = link_to_admin_events
  end

  private

  def any_items?
    @items.size.positive?
  end

  def grid_classes
    @col_size == 8 ? wide_column_classes : full_width_classes
  end

  # The home page's two-thirds column caps at three across, and four read better
  # as 2x2 than as three and a widow.
  def wide_column_classes
    amount = @items.size == 4 ? 2 : @items.size

    case [ 3, amount ].min
    when 1 then "grid grid-cols-1 gap-3"
    when 2 then "grid grid-cols-1 md:grid-cols-2 gap-3"
    else        "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3"
    end
  end

  def full_width_classes
    case [ 4, @items.size ].min
    when 1 then "grid grid-cols-1 gap-3"
    when 2 then "grid grid-cols-1 sm:grid-cols-2 gap-3"
    when 3 then "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
    else        "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3"
    end
  end

  def url_for_item(item)
    @link_to_admin_events ? [ :admin, item[:event] ] : item[:event]
  end

  def srcset_variants
    [ helpers.thumb_variant_public, helpers.medium_variant, helpers.slideshow_variant ]
  end
end
