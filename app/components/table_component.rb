# A plain table. `field_sets` is a list of { class:, fields: [] }; cells render as given.
# A Symbol header is a simple_form label translation key, and a sort link when a
# ransack object is passed. IndexTableComponent wraps this for resource indexes.
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
