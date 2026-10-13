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

  test "the grid uses as many columns as it has events, up to the column's cap" do
    { [ 5, 12 ] => "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3",
      [ 2, 12 ] => "grid grid-cols-1 sm:grid-cols-2 gap-3",
      [ 5, 8 ] => "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3",
      [ 4, 8 ] => "grid grid-cols-1 md:grid-cols-2 gap-3" # 2x2, rather than a row of three and a widow
    }.each do |(count, col_size), classes|
      render_grid(count, col_size)

      assert_selector "div[class='#{classes}']"
    end
  end

  # h-auto on the image would fight the crop box's h-full.
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
end
