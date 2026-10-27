require "test_helper"

# The app overrides every Kaminari partial with strict locals, so each must accept what `paginate`
# passes, and the links must carry its `data:` option as Kaminari's own templates do.
class KaminariPaginatorTest < ActionView::TestCase
  setup { controller.request.path_parameters = { controller: "news", action: "index" } }

  test "paginate's data option reaches every page link" do
    render inline: "<%= paginate(Kaminari.paginate_array((1..50).to_a).page(3).per(10), data: { turbo_frame: 'results' }) %>"

    links = css_select("nav[aria-label='Page Navigation'] a")
    assert_operator links.size, :>=, 4 # First, Prev, Next, Last at least
    assert links.all? { |link| link["data-turbo-frame"] == "results" }, "every page link carries data-turbo-frame"
  end
end
