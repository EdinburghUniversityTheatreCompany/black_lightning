class IndexTableComponentPreview < Admin::ApplicationComponentPreview
  def default
    render IndexTableComponent.new(headers: [ :name ], field_sets: venue_rows, resource_class: Venue)
  end

  # Proposals do this: the record is still passed (the edit permission checks it) but its cell is dropped.
  def without_the_item_link
    render IndexTableComponent.new(headers: [], field_sets: venue_rows,
                                   resource_class: Venue, include_link_to_item: false)
  end

  def without_the_edit_button
    render IndexTableComponent.new(headers: [ :name ], field_sets: venue_rows,
                                   resource_class: Venue, include_edit_button: false)
  end

  private

  def venue_rows
    Venue.limit(5).map { |venue| { fields: [ venue ] } }
  end
end
