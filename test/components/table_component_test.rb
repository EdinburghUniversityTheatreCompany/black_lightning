require "test_helper"

class TableComponentTest < ViewComponent::TestCase
  test "renders a row per field set and a cell per field" do
    render_inline(TableComponent.new(
      headers: [ "One", "Two" ],
      field_sets: [ { fields: [ "a", "b" ] }, { class: "danger", fields: [ "c", "d" ] } ]
    ))

    assert_selector "tbody tr", count: 2
    assert_selector "tbody tr.danger td", count: 2
    assert_selector "thead th", count: 2
  end

  # A Symbol header is a simple_form translation key; anything else is literal.
  test "symbol headers are translated, others left alone" do
    render_inline(TableComponent.new(headers: [ :name, "Literal" ], field_sets: []))

    assert_selector "th", text: I18n.t("simple_form.labels.defaults.name")
    assert_selector "th", text: "Literal"
  end

  # sort_link builds a URL against the current request, so the test needs one.
  test "headers become sort links when there is something to sort" do
    with_request_url "/admin/venues" do
      render_inline(TableComponent.new(headers: [ :name ], field_sets: [], q: Venue.ransack))
    end

    assert_selector "th a.sort_link"
  end

  test "without a ransack object a header is plain text" do
    render_inline(TableComponent.new(headers: [ :name ], field_sets: []))

    assert_no_selector "th a"
  end

  test "column widths switch the table to a fixed layout" do
    render_inline(TableComponent.new(headers: [ "a" ], field_sets: [], col_widths: [ "70%", "30%" ]))

    assert_selector "table[style*='table-layout: fixed']"
    assert_selector "colgroup col", count: 2
  end

  test "headers can be suppressed entirely" do
    render_inline(TableComponent.new(headers: [ "One" ], field_sets: [], include_headers: false))

    assert_no_selector "thead"
  end
end
