class EventsGridComponentPreview < ViewComponent::Preview
  # A venue or profile page: the grid has the full width to work with.
  def full_width
    render EventsGridComponent.new(items: build_items(8), col_size: 12)
  end

  def single
    render EventsGridComponent.new(items: build_items(1), col_size: 12)
  end

  # The home page's two-thirds column, which caps at three across.
  def wide_column
    render EventsGridComponent.new(items: build_items(6), col_size: 8)
  end

  # Four events in that column lay out 2x2 rather than three and a widow.
  def wide_column_with_four
    render EventsGridComponent.new(items: build_items(4), col_size: 8)
  end

  private

  def build_items(limit)
    Event.where(is_public: true).limit(limit).map do |event|
      {
        event: event,
        paragraphs: [
          { content: event.date_range(true), small: true },
          { content: event.short_blurb }
        ]
      }
    end
  end
end
