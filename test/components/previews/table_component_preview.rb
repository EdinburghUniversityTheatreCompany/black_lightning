class TableComponentPreview < ViewComponent::Preview
  def default
    render TableComponent.new(
      headers: [ "Name", "Role" ],
      field_sets: [
        { fields: [ "Alice Jones", "Stage Manager" ] },
        { fields: [ "Patrick Brennan", "Director" ] }
      ]
    )
  end

  # A row can carry its own class, for a highlighted or muted state.
  def with_row_classes
    render TableComponent.new(
      headers: [ "Name", "Status" ],
      field_sets: [
        { fields: [ "Alice Jones", "Fine" ] },
        { class: "danger", fields: [ "Patrick Brennan", "In debt" ] }
      ]
    )
  end

  # Fixed widths switch the table to table-layout: fixed.
  def with_column_widths
    render TableComponent.new(
      headers: [ "Question", "Type" ],
      field_sets: [ { fields: [ "Why do you want to direct this?", "Long Text" ] } ],
      col_widths: [ "70%", "30%" ]
    )
  end

  def without_headers
    render TableComponent.new(
      headers: [ "Name" ],
      field_sets: [ { fields: [ "Alice Jones" ] } ],
      include_headers: false
    )
  end
end
