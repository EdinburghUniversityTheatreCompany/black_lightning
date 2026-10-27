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

  test "symbol headers are translated, others left alone, and neither links without ransack" do
    render_inline(TableComponent.new(headers: [ :name, "Literal" ], field_sets: []))

    assert_selector "th", text: I18n.t("simple_form.labels.defaults.name")
    assert_selector "th", text: "Literal"
    assert_no_selector "th a"
  end

  # sort_link builds a URL against the current request, so the test needs one.
  test "headers become sort links when there is something to sort" do
    with_request_url "/admin/venues" do
      render_inline(TableComponent.new(headers: [ :name ], field_sets: [], q: Venue.ransack))
    end

    assert_selector "th a.sort_link"
  end

  # GHSA-58rx-96gf-w92x: ransack < 6.0.1 passed these params to url_for
  test "sort links ignore url options smuggled in through the query string" do
    with_request_url "/admin/venues?script_name=javascript:alert(1)//&host=evil.example&only_path=false" do
      render_inline(TableComponent.new(headers: [ :name ], field_sets: [], q: Venue.ransack))
    end

    assert_selector "th a.sort_link[href^='/admin/venues?']"
  end

  test "column widths switch the table to a fixed layout" do
    render_inline(TableComponent.new(headers: [ "a" ], field_sets: [], col_widths: [ "70%", "30%" ]))

    assert_selector "table[style*='table-layout: fixed']"
    assert_selector "colgroup col", count: 2
  end
end
