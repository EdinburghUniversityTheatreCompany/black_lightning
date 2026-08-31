require "test_helper"

##
# The dated list on a public event page.
#
# It used to render Event::Schedule's collapsed BLOCKS -- "Wed 23 - Sat 26
# September, 7pm" -- with the relaxed and cancelled nights named in a separate
# list underneath. On a run with a midnight show that reads as a contradiction:
# the Friday and Saturday appear in two overlapping ranges, and nothing says
# those nights have two performances. Every performance now gets its own row,
# with its own badges, so there is nothing to cross-reference.
##
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

  test "every performance gets its own row" do
    (23..26).each { |day| perform!(day, 19) }
    [ 25, 26 ].each { |day| perform!(day, 23, 45) }

    rows = performance_rows

    assert_equal 6, rows.length
    assert_match(/Wednesday 23 September/, rows.first)
    assert_match(/7pm/, rows.first)
  end

  test "two performances on one night are two rows, in time order" do
    perform!(25, 23, 45)
    perform!(25, 19)

    rows = performance_rows

    assert_equal 2, rows.length
    assert_match(/7pm/, rows[0])
    assert_match(/11.45pm/, rows[1])
  end

  test "a cancelled night is named on its own row" do
    perform!(23, 19)
    perform!(24, 19, 0, cancelled: true)

    rows = performance_rows

    assert_no_match(/Cancelled/i, rows[0])
    assert_match(/Cancelled/i, rows[1])
  end

  test "a sold-out night is named on its own row" do
    perform!(23, 19, 0, sold_out: true)

    assert_match(/Sold out/i, performance_rows.sole)
  end

  test "access flags and the note ride on the performance they belong to" do
    perform!(23, 19)
    perform!(24, 19, 0, access_flags: [ "relaxed", "captioned" ], note: "Q&A afterwards")

    rows = performance_rows

    assert_match(/Relaxed/, rows[1])
    assert_match(/Captioned/, rows[1])
    assert_match(/Q&A afterwards/, rows[1])
    assert_no_match(/Relaxed/, rows[0])
  end

  # The separate list existed only because the collapsed range hid which night
  # was which. Keeping it as well would say everything twice.
  test "the old cross-reference list is gone" do
    perform!(23, 19, 0, access_flags: [ "relaxed" ])

    get show_path(@show)

    assert_no_match(/Relaxed:/, response.body)
  end

  # Every archive row, and any show whose producer has not filled the times in.
  test "an event with no performances still states its run" do
    get show_path(@show)

    assert_response :success
    assert_empty css_select("[data-performance]")
    assert_match(/23 September|Wed 23/, response.body)
  end

  test "a past performance is still listed" do
    # Mick's call: every date, so a producer can check what the sync pulled in
    # and an audience can see what the run was.
    @show.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))
    FactoryBot.create(:event_occurrence, event: @show, starts_at: Time.zone.local(2026, 1, 5, 19))

    assert_equal 1, performance_rows.length
  end
end
