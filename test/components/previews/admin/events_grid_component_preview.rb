class Admin::EventsGridComponentPreview < Admin::ApplicationComponentPreview
  # A single show card
  def single
    render Admin::EventsGridComponent.new(items: build_items(1), col_size: 12, link_to_admin_events: true)
  end

  # Full grid with many shows
  def full_grid
    render Admin::EventsGridComponent.new(items: build_items(8), col_size: 12, link_to_admin_events: true)
  end

  private

  def build_items(limit)
    TeamMember.where(teamwork_type: "Show").includes(:teamwork).limit(limit).filter_map do |tm|
      next unless tm.teamwork.present?

      {
        event: tm.teamwork,
        paragraphs: [
          { content: tm.teamwork.date_range(true), small: true },
          { content: tm.teamwork.short_blurb },
          { content: "<b>Position</b>: #{tm.position}".html_safe, class: "mt-auto" }
        ]
      }
    end
  end
end
