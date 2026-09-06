# A resource index's table: the first cell of each row is the record itself,
# which this turns into a link to it and — where the viewer may edit it — hangs
# an Edit button off the end of the row.
#
# Everything is computed into new arrays. The partial this replaced wrote into
# the caller's own `headers` and `field_sets` (`headers << ''`,
# `fields << get_link(...)`, `fields[0] = ...`), so rendering the same spec
# twice appended a second Edit button and re-wrapped an already-linked cell.
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

  # The blank header sits above the Edit column.
  def headers
    edit_column? ? @headers + [ "" ] : @headers
  end

  def edit_column?
    @include_edit_button && helpers.can?(:edit, @resource_class)
  end

  def field_sets
    @field_sets.map { |field_set| field_set.merge(fields: cells_for(field_set[:fields])) }
  end

  # fields[0] is the record. It is either linked in place, or dropped — a caller
  # that does not want the link still has to pass it, because it is what the
  # edit permission is checked against.
  def cells_for(fields)
    record = fields.first
    rest = fields.drop(1)

    cells = @include_link_to_item ? [ helpers.get_link(record, :show), *rest ] : rest
    cells << helpers.get_link(record, :edit) if @include_edit_button && helpers.can?(:edit, record)
    cells
  end
end
