require "test_helper"

# One row per performance with its own badges, rather than Event::Schedule's
# collapsed blocks.
class EventPerformancesTest < ActionDispatch::IntegrationTest
  setup do
    @show = FactoryBot.create(:show, name: "The Rocky Horror Show", is_public: true,
                                     start_date: Date.new(2026, 9, 23), end_date: Date.new(2026, 9, 26))
  end

  def perform!(day, hour, minute = 0, **attributes)
    FactoryBot.create(:event_occurrence, event: @show,
                                         starts_at: Time.zone.local(2026, 9, day, hour, minute),
                                         **attributes)
  end

  def performance_rows
    get show_path(@show)
    css_select("[data-performance]").map { |node| node.text.split.join(" ") }
  end

  test "a sold-out night is named on its own row" do
    perform!(23, 19, 0, sold_out: true)

    assert_match(/Sold out/i, performance_rows.sole)
  end

  # Every archive row, and any show whose producer has not filled the times in.
  test "an event with no performances still states its run" do
    get show_path(@show)

    assert_response :success
    assert_empty css_select("[data-performance]")
    assert_match(/23 September|Wed 23/, response.body)
  end

  test "a past performance is still listed" do
    # Every date, so a producer can check what the sync pulled in.
    @show.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 1, 5, 19))

    assert_equal 1, performance_rows.length
  end
end
