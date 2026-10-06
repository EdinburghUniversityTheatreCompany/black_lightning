# A resource index's table: each row's first cell is the record, linked to it,
# with an Edit button at the end of the row where the viewer may edit it.
# Builds new arrays and never mutates the caller's `headers` or `field_sets`:
# rendering one spec twice must not add a second Edit button.
class IndexTableComponent < ViewComponent::Base
  def initialize(headers:, field_sets:, resource_class:, q: nil,
                 include_edit_button: true, include_link_to_item: true, col_widths: [])
    @headers = headers
    @field_sets = field_sets
    @resource_class = resource_class
    @q = q
    @include_edit_button = include_edit_button
    @include_link_to_item = include_link_to_item
    @col_widths = col_widths
  end

  private

  def headers
    edit_column? ? @headers + [ "" ] : @headers
  end

  def edit_column?
    @include_edit_button && helpers.can?(:edit, @resource_class)
  end

  def field_sets
    @field_sets.map { |field_set| field_set.merge(fields: cells_for(field_set[:fields])) }
  end

  # fields[0] is the record, linked or dropped. A caller wanting no link must still
  # pass it: the edit permission is checked against it.
  def cells_for(fields)
    record = fields.first
    rest = fields.drop(1)

    cells = @include_link_to_item ? [ helpers.get_link(record, :show), *rest ] : rest
    cells << helpers.get_link(record, :edit) if @include_edit_button && helpers.can?(:edit, record)
    cells
  end
end
