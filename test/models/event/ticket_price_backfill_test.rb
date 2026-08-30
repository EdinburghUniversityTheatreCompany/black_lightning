require "test_helper"

class Event::TicketPriceBackfillTest < ActiveSupport::TestCase
  def show(price:, start_date: Date.new(2016, 3, 1), **attributes)
    FactoryBot.create(:show, price: price, start_date: start_date,
                             end_date: start_date + 4, **attributes)
  end

  def backfill(apply: false)
    Event::TicketPriceBackfill.call(apply: apply)
  end

  setup { Event.unscoped.delete_all }

  test "a dry run reads everything and writes nothing" do
    event = show(price: "£10/8/7")

    summary = backfill

    assert_equal 1, summary.parsed
    assert_not summary.applied
    assert_equal [], event.reload.ticket_prices
  end

  test "applying writes the structured bands" do
    event = show(price: "£10/8/7")

    summary = backfill(apply: true)

    assert_equal 1, summary.parsed
    assert summary.applied
    assert_equal [ [ 10.0, "standard" ], [ 8.0, "concession" ], [ 7.0, "member" ] ],
                 event.reload.ticket_prices.map { |p| [ p.amount.to_f, p.category ] }
  end

  # The whole reason the backfill uses update_columns. Rewriting price would
  # change the visible text on ~3000 archive pages for no gain.
  test "applying never rewrites the display string" do
    event = show(price: "10/8/7")

    backfill(apply: true)

    assert_equal "10/8/7", event.reload.price
  end

  test "applying stores a booking fee where the string carried one" do
    event = show(price: "£2/3/4 + £1 booking fee on the door")

    backfill(apply: true)

    assert_equal BigDecimal("1"), event.reload.booking_fee
  end

  # THE trap. "3/6" on a 1962 show is 3s 6d, and nothing in the string says so --
  # only the date can. Every row before decimalisation is refused whether or not
  # the parser could make something of it.
  test "refuses everything before decimalisation, however readable the string" do
    old = show(price: "3/6", start_date: Date.new(1962, 8, 21))

    summary = backfill(apply: true)

    assert_equal 1, summary.pre_decimal
    assert_equal 0, summary.parsed
    assert_equal [], old.reload.ticket_prices
  end

  test "a row on the day of decimalisation is in the decimal era" do
    event = show(price: "£5/4", start_date: Event::PriceParser::DECIMALISATION_DATE)

    backfill(apply: true)

    assert_equal 2, event.reload.ticket_prices.size
  end

  test "an undated row is refused rather than guessed at" do
    event = show(price: "£10/8")
    event.update_columns(start_date: nil)

    summary = backfill(apply: true)

    assert_equal 1, summary.pre_decimal
    assert_equal [], event.reload.ticket_prices
  end

  test "counts what it could not read, by string, and writes none of it" do
    show(price: "Unknown")
    show(price: "Unknown")
    show(price: "TBC")

    summary = backfill(apply: true)

    assert_equal 0, summary.parsed
    assert_equal 3, summary.unreadable
    assert_equal({ "Unknown" => 2, "TBC" => 1 }, summary.unreadable_counts)
  end

  # Re-running after a parser change must not overwrite a band someone typed by
  # hand in the admin.
  test "leaves an event that already has bands alone" do
    event = show(price: "£10/8/7")
    event.update!(ticket_prices: [ { "category" => "standard", "amount" => "99" } ])

    summary = backfill(apply: true)

    assert_equal 0, summary.considered
    assert_equal [ 99.0 ], event.reload.ticket_prices.map { |p| p.amount.to_f }
  end

  test "reports a sample of what each readable string became" do
    show(price: "£10/8/7")

    summary = backfill

    assert_equal "£10 / £8 concessions / £7 members", summary.parsed_samples.fetch("£10/8/7")
  end
end
