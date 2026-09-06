# A plain table. `field_sets` is a list of { class:, fields: [] } — cells are
# rendered as given, so a caller builds whatever it wants in them.
#
# A Symbol header is looked up in simple_form's label translations, and becomes
# a sort link when a ransack object is passed; anything else is rendered as is.
# IndexTableComponent wraps this to add the show/edit links a resource index
# needs.
class TableComponent < ViewComponent::Base
  def initialize(headers:, field_sets:, q: nil, table_class: "table-hover",
                 include_headers: true, col_widths: [])
    @headers = headers
    @field_sets = field_sets
    @q = q
    @table_class = table_class
    @include_headers = include_headers
    @col_widths = col_widths
  end

  private

  # A new array — the caller's headers are never written to.
  def rendered_headers
    @headers.map do |header|
      next header unless header.is_a?(Symbol)

      text = I18n.t("simple_form.labels.defaults.#{header}")
      @q.present? ? helpers.sort_link(@q, header, text) : text
    end
  end

  def fixed_layout?
    @col_widths.any?
  end
end
