require "test_helper"

# Every string here is a real shape from the production events table.
class Event::PriceParserTest < ActiveSupport::TestCase
  def parse(string)
    Event::PriceParser.parse(string)
  end

  # [amount, category] pairs, dearest first, so a failure names what it read.
  def bands(string)
    parse(string)&.prices&.map { |price| [ price.amount.to_f, price.category ] }
  end

  # Both orderings occur, so categories go by AMOUNT, never position.
  test "reads a three-band price written cheapest-first or dearest-first" do
    expected = [ [ 5.0, "standard" ], [ 4.0, "concession" ], [ 3.0, "member" ] ]

    assert_equal expected, bands("3/4/5")
    assert_equal expected, bands("5/4/3")
    assert_equal expected, bands("£3/4/5")
    assert_equal expected, bands("£5/£4/£3")
  end

  test "reads a two-band price" do
    assert_equal [ [ 5.0, "standard" ], [ 4.5, "concession" ] ], bands("4.50/5.00")
    assert_equal [ [ 6.0, "standard" ], [ 5.0, "concession" ] ], bands("£6/£5")
  end

  test "reads a single amount as the standard band" do
    assert_equal [ [ 2.5, "standard" ] ], bands("£2.50")
    assert_equal [ [ 4.0, "standard" ] ], bands("4.00")
  end

  test "reads the double-slash separator" do
    assert_equal [ [ 3.0, "standard" ], [ 2.5, "concession" ] ], bands("£3.00 // £2.50")
  end

  test "tolerates spacing around the currency symbol and separators" do
    assert_equal [ [ 5.0, "standard" ], [ 4.5, "concession" ], [ 4.0, "member" ] ],
                 bands("£5.00 / £4.50 / £4.00")
    assert_equal [ [ 3.0, "standard" ], [ 2.5, "concession" ] ], bands("£ 3 / 2.50 ")
  end

  # Pre-decimal pence is "d", so a "p" past the date gate is decimal.
  test "reads pence" do
    assert_equal [ [ 0.3, "standard" ] ], bands("30p")
  end

  test "a named band wins over its position" do
    assert_equal [ [ 8.0, "standard" ], [ 6.0, "concession" ] ], bands("£8 / £6 concessions")
    assert_equal [ [ 3.0, "standard" ], [ 2.5, "concession" ] ], bands("£3 (£2.50 concessions)")
  end

  test "reads the parenthetical members band" do
    assert_equal [ [ 5.0, "standard" ], [ 4.4, "concession" ], [ 4.0, "member" ] ],
                 bands("£5/£4.40 (£4 Members)")
  end

  test "a band named with a word we do not have a category for becomes other" do
    result = parse("£12.00 full price, £10.00 student")

    assert_equal [ [ 12.0, "standard" ], [ 10.0, "other" ] ], result.prices.map { |p| [ p.amount.to_f, p.category ] }
    assert_equal "Student", result.prices.last.label
  end

  test "free is a zero standard band" do
    [ "Free", "FREE", "free", "Free!", "Free Unticketed", "0" ].each do |text|
      assert_equal [ [ 0.0, "standard" ] ], bands(text), text.inspect
    end
  end

  # "Free / donations" is pay-what-you-can, which is not the same promise as free.
  test "free with anything else attached is refused" do
    assert_nil parse("Free / donations")
    assert_nil parse("Donation-based")
    assert_nil parse("Pay-what-you-can (all proceeds to charity)")
  end

  test "strips a booking fee off the end and records it" do
    result = parse("£2/3/4 + £1 booking fee on the door")

    assert_equal [ [ 4.0, "standard" ], [ 3.0, "concession" ], [ 2.0, "member" ] ],
                 result.prices.map { |p| [ p.amount.to_f, p.category ] }
    assert_equal 1, result.booking_fee
  end

  test "reads every fee suffix that occurs in the archive" do
    { "£5/6/7 + £1 on the door" => 1,
      "5/6/7 (+1 on the door)" => 1,
      "£4/5/8 +£1 booking fee" => 1,
      "£4/£5/£8 + fees, £1 booking fee on the door" => 1,
      "£4/5/8 + £1 booking fee on the door." => 1 }.each do |text, fee|
      assert_equal fee, parse(text)&.booking_fee, text.inspect
    end
  end

  # "+ fees" names no figure, so the fee is nil but the prices still read.
  test "a fee with no figure leaves the fee unknown but keeps the prices" do
    [ "£7/8/9 + fees", "£2/3/4+fees", "£10+fees" ].each do |text|
      result = parse(text)

      assert_not_nil result, text.inspect
      assert_nil result.booking_fee, text.inspect
    end
  end

  # "2/6, 3/6, 5/-" is shillings and pence, not five prices. The date gate is the
  # main defence; this is the second.
  test "refuses shillings and pence" do
    [ "2/-, 3/-, 4/-", "3/6, 4/6, 6/-", "6/-", "6d", "4s, 3s, 2s",
      "3s 6d, 5s, 6s 6d", "5/-, 10/- if not in fancy dress", "3s, 4s, 5s 6d" ].each do |text|
      assert_nil parse(text), "#{text.inspect} is pre-decimal and must be refused"
    end
  end

  # "3/6, 2/6" has no shilling marker. Four unnamed amounts are refused anyway,
  # but only the date gate catches these on purpose.
  test "refuses more amounts than there are bands to name" do
    assert_nil parse("1/2/3/4")
    assert_nil parse("3/6, 2/6")
  end

  test "refuses the placeholders" do
    [ "Unknown", "unknown", "TBC", "TBD", "N/A", "?", "??", "--", "-",
      "Various", "Varying", "asdsds", "Fere", "" ].each do |text|
      assert_nil parse(text), text.inspect
    end
  end

  test "refuses anything with prose left over after the prices" do
    [ "from £9.38", "From £5", "£7 all/ £2.50 each", "£8 with a cocktail, £4 without",
      "Fri/Mon 4.00/3.00/2.00, Thu 3.00/2.50/2.00",
      "Subscription ticket £99 for students, £135 for adults",
      "Tickets prices to be £3/4/5 with £1 ticket fee if paying on door",
      "£3/£3.50 or 3 tickets for £7.",
      "£2/£3 + fees; £3/4/5 + fees in person" ].each do |text|
      assert_nil parse(text), "#{text.inspect} has unread prose and must be refused"
    end
  end

  # Not sterling, so we cannot claim to have read it.
  test "refuses a foreign currency" do
    assert_nil parse("$5")
  end

  test "refuses nil" do
    assert_nil parse(nil)
  end

  # Both read as ordinary output: "150" is £1.50 without the dot, and "1/75" is
  # £1.75, not a 75x spread between two bands.
  test "refuses an amount too large to be a ticket here" do
    assert_nil parse("150")
    assert_nil parse("£120/100")
  end

  test "refuses an implausible spread between bands" do
    assert_nil parse("1/75")
  end

  test "keeps a wide but believable spread, and a believable single amount" do
    assert_equal [ [ 17.0, "standard" ], [ 2.0, "concession" ] ], bands("2.00/17.00")
    assert_equal [ [ 45.0, "standard" ] ], bands("£45")
  end

  # A free band alongside a paid one has no ratio to speak of, and is a real thing.
  test "a zero band does not count towards the spread" do
    assert_equal [ [ 1.5, "standard" ], [ 0.0, "concession" ] ], bands("0/1.50")
  end

  test "produces TicketPrices that are themselves valid" do
    parse("£10/8/7").prices.each { |price| assert_predicate price, :valid? }
  end

  test "amounts are exact decimals, never floats" do
    price = parse("£4.35").prices.first

    assert_kind_of BigDecimal, price.amount
    assert_equal BigDecimal("4.35"), price.amount
  end
end
