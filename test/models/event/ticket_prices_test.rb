require "test_helper"

##
# The events.ticket_prices JSON column. fields_for edits it as an association
# because Event answers to ticket_prices_attributes=.
##
class Event::TicketPricesTest < ActiveSupport::TestCase
  setup do
    @show = FactoryBot.create(:show, price: "£10/8/7")
  end

  def bands(event)
    event.ticket_prices.map { |price| [ price.amount.to_f, price.category ] }
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

  # The form's template always posts one blank row.
  test "a row with no amount is dropped rather than stored" do
    @show.update!(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10" },
      "1" => { "category" => "standard", "amount" => "" }
    })

    assert_equal [ [ 10.0, "standard" ] ], bands(@show.reload)
  end

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

  # A curator can still type something no set of bands expresses.
  test "a hand-typed price survives when no bands are entered" do
    @show.update!(price: "Pay what you can")

    assert_equal "Pay what you can", @show.reload.price
    assert_equal [], @show.reload.ticket_prices
  end

  # "ten" is rejected, not cast to 0, or one typo would advertise a paid show as Free.
  test "an invalid band is rejected" do
    [ { "category" => "standard", "amount" => "-5" },
      { "category" => "bogus", "amount" => "5" },
      { "category" => "standard", "amount" => "ten" } ].each do |row|
      @show.ticket_prices_attributes = { "0" => row }

      assert_not @show.valid?, row.inspect
      assert @show.errors[:ticket_prices].present?, row.inspect
    end
  end

  test "a genuine zero is still allowed" do
    @show.ticket_prices_attributes = { "0" => { "category" => "standard", "amount" => "0" } }

    assert_predicate @show, :valid?
  end

  test "a price written with the currency mark is read, not rejected" do
    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "£10" } })

    assert_equal [ 10.0 ], @show.reload.ticket_prices.map { |price| price.amount.to_f }
  end

  # A Show validates price, so clearing a derived one fails the save and asks for
  # the new price.
  test "clearing the bands clears the price they wrote" do
    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "10" } })
    assert_equal "£10", @show.reload.price

    assert_not @show.update(ticket_prices_attributes: {
      "0" => { "category" => "standard", "amount" => "10", "_destroy" => "1" }
    })

    assert_nil @show.price
    assert @show.errors[:price].present?
  end

  # ...but a string somebody typed by hand is theirs, not ours to remove.
  test "clearing the bands empties the column and leaves a hand-typed price alone" do
    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "10" } })
    @show.update!(price: "Pay what you can")

    @show.update!(ticket_prices_attributes: { "0" => { "category" => "standard", "amount" => "10", "_destroy" => "1" } })

    assert_equal [], @show.reload.ticket_prices
    assert_equal "Pay what you can", @show.price
  end
end
