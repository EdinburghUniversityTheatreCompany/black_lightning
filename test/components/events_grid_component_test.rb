require "test_helper"

class EventsGridComponentTest < ViewComponent::TestCase
  def items(count)
    Array.new(count) do
      { event: FactoryBot.create(:show), paragraphs: [ { content: "blurb" } ] }
    end
  end

  def render_grid(count, col_size)
    render_inline(EventsGridComponent.new(items: items(count), col_size: col_size))
  end

  test "renders nothing when there are no events" do
    render_inline(EventsGridComponent.new(items: [], col_size: 12))

    assert_no_selector "div.grid"
  end

  test "a full-width grid opens up to four columns" do
    render_grid(5, 12)

    assert_selector "div.grid.grid-cols-1.sm\\:grid-cols-2.md\\:grid-cols-3.lg\\:grid-cols-4"
  end

  test "a full-width grid uses only as many columns as it has events" do
    render_grid(2, 12)

    assert_selector "div.grid.grid-cols-1.sm\\:grid-cols-2"
    assert_no_selector "div.md\\:grid-cols-3"
  end

  test "the home page's narrower column caps at three across" do
    render_grid(5, 8)

    assert_selector "div.grid.grid-cols-1.md\\:grid-cols-2.lg\\:grid-cols-3"
    assert_no_selector "div.lg\\:grid-cols-4"
  end

  # Four in that column lay out 2x2, rather than a row of three and a widow.
  test "four events in the narrower column lay out two by two" do
    render_grid(4, 8)

    assert_selector "div.grid.grid-cols-1.md\\:grid-cols-2"
    assert_no_selector "div.lg\\:grid-cols-3"
  end

  # Posters are cropped to a fixed ratio so a row of cards lines up. The image
  # must not also carry h-auto, or it fights the crop box's h-full.
  test "posters are cropped to a fixed ratio" do
    render_grid(1, 12)

    assert_selector "div.aspect-\\[576\\/300\\].overflow-hidden img.object-cover.h-full"
    assert_no_selector "img.h-auto"
  end

  # Cropping must not cost the responsive sources or the alt text.
  test "cards still offer smaller sources and name the theatre in the alt" do
    render_grid(1, 12)

    assert_selector "img[srcset][sizes]"
    assert_selector "img[alt$='at Bedlam Theatre']"
  end

  test "the title link carries the primary colour" do
    render_grid(1, 12)

    assert_selector "a.font-semibold.text-primary"
  end
end
