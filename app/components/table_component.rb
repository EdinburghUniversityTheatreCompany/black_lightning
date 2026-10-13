# A plain table. `field_sets` is a list of { class:, fields: [] }; cells render as given.
# A Symbol header is a simple_form label translation key, and a sort link when a
# ransack object is passed. IndexTableComponent wraps this for resource indexes.
class TableComponent < ViewComponent::Base
  def initialize(headers:, field_sets:, q: nil, col_widths: [])
    @headers = headers
    @field_sets = field_sets
    @q = q
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
