require "test_helper"

##
# The events.ticket_prices JSON column, and the nested-attributes seam that lets
# the existing admin nested-form UI edit it as if it were an association.
##
class Event::TicketPricesTest < ActiveSupport::TestCase
  setup do
    @show = FactoryBot.create(:show, price: "£10/8/7")
  end

  def bands(event)
    event.ticket_prices.map { |price| [ price.amount.to_f, price.category ] }
  end

  test "an event with nothing entered has no ticket prices" do
    assert_equal [], FactoryBot.build(:show).ticket_prices
  end

  test "ticket prices round-trip through the database as exact decimals" do
    @show.update!(ticket_prices: [
      Event::TicketPrice.new(category: "standard", amount: BigDecimal("10.50")),
      Event::TicketPrice.new(category: "member", amount: BigDecimal("7"))
    ])

    reloaded = @show.reload.ticket_prices

    assert_equal [ BigDecimal("10.50"), BigDecimal("7") ], reloaded.map(&:amount)
    assert_kind_of BigDecimal, reloaded.first.amount
  end

  test "ticket prices come back dearest first however they were entered" do
    @show.update!(ticket_prices: [
      { "category" => "member", "amount" => "7" },
      { "category" => "standard", "amount" => "10" },
      { "category" => "concession", "amount" => "8" }
    ])

    assert_equal [ [ 10.0, "standard" ], [ 8.0, "concession" ], [ 7.0, "member" ] ], bands(@show.reload)
  end

  # --- the nested-attributes seam ---------------------------------------

  # fields_for treats a plain method as an association as soon as the parent
  # responds to `<name>_attributes=`, which is the whole trick: the JSON column
  # is edited by the same nested-form UI as a real has_many.
  test "the event answers to the nested-attributes writer fields_for looks for" do
    assert_respond_to @show, :ticket_prices_attributes=
  end

  test "accepts the params shape the nested form posts" do
    @show.update!(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10" },
      "1" => { "category" => "concession", "amount" => "8" }
    })

    assert_equal [ [ 10.0, "standard" ], [ 8.0, "concession" ] ], bands(@show.reload)
  end

  test "a row marked for destruction is dropped" do
    @show.update!(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10" },
      "1" => { "category" => "concession", "amount" => "8", "_destroy" => "1" }
    })

    assert_equal [ [ 10.0, "standard" ] ], bands(@show.reload)
  end

  # The nested form always posts one blank row from its template; saving it would
  # store a band with no price.
  test "a row with no amount is dropped rather than stored" do
    @show.update!(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10" },
      "1" => { "category" => "standard", "amount" => "" }
    })

    assert_equal [ [ 10.0, "standard" ] ], bands(@show.reload)
  end

  test "clearing every row empties the column" do
    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "10" } })
    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "10", "_destroy" => "1" } })

    assert_equal [], @show.reload.ticket_prices
  end

  # --- the derived display string ---------------------------------------

  # price stays the string every existing view renders. Editing the structured
  # bands regenerates it, so the two cannot drift; the backfill deliberately does
  # not, which is why the archive keeps rendering byte-identically.
  test "saving structured prices rewrites the display string" do
    @show.update!(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10" },
      "1" => { "category" => "concession", "amount" => "8" },
      "2" => { "category" => "member", "amount" => "7" }
    })

    assert_equal "£10 / £8 concessions / £7 members", @show.reload.price
  end

  test "the display string keeps the pence only where there are any" do
    @show.update!(ticket_prices: [ { "category" => "standard", "amount" => "4.50" } ])

    assert_equal "£4.50", @show.reload.price
  end

  test "an other band is named by its own label" do
    @show.update!(ticket_prices: [
      { "category" => "standard", "amount" => "12" },
      { "category" => "other", "label" => "Student", "amount" => "10" }
    ])

    assert_equal "£12 / £10 Student", @show.reload.price
  end

  test "bands that are all free read as Free" do
    @show.update!(ticket_prices: [ { "category" => "standard", "amount" => "0" } ])

    assert_equal "Free", @show.reload.price
  end

  test "leaving the structured bands alone leaves the display string alone" do
    @show.update!(tagline: "A new tagline")

    assert_equal "£10/8/7", @show.reload.price
  end

  # A curator can still type something no set of bands expresses.
  test "a hand-typed price survives when no bands are entered" do
    @show.update!(price: "Pay what you can")

    assert_equal "Pay what you can", @show.reload.price
    assert_equal [], @show.reload.ticket_prices
  end

  # --- the booking fee ---------------------------------------------------

  test "a booking fee is stored alongside the bands" do
    @show.update!(booking_fee: BigDecimal("1"))

    assert_equal BigDecimal("1"), @show.reload.booking_fee
  end
end
