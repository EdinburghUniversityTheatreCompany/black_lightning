##
# Reads the free-text events.price column into structured ticket_prices for every
# archive row the parser can read completely.
#
# Dry by default. `bin/rails events:backfill_ticket_prices` prints the report;
# APPLY=1 writes. Review the report against production before applying it -- the
# parser refuses rather than guesses, and the report is where you check that its
# refusals are the ones you expect.
#
# Writes with update_columns, so ONLY ticket_prices and booking_fee move. price
# keeps whatever it says today, which is what stops ~3000 archive pages changing
# the text they render. Editing the bands in the admin does regenerate it; see
# Event#derive_price_from_ticket_prices.
##
class Event::TicketPriceBackfill
  Summary = Data.define(:considered, :parsed, :pre_decimal, :unreadable,
                        :unreadable_counts, :parsed_samples, :applied)

  # Events that have a price written down and no structured bands yet. Skipping
  # rows that already have bands makes a re-run after a parser change safe: it
  # cannot overwrite something a producer typed by hand.
  def self.scope
    Event.unscoped.where.not(price: [ nil, "" ]).where(ticket_prices: nil)
  end

  def self.call(apply: false)
    new(apply: apply).call
  end

  def initialize(apply: false)
    @apply = apply
    @considered = 0
    @parsed = 0
    @pre_decimal = 0
    @unreadable_counts = Hash.new(0)
    @parsed_samples = {}
  end

  def call
    self.class.scope.find_each do |event|
      @considered += 1

      next record_pre_decimal unless Event::PriceParser.decimal_era?(event.start_date)

      result = Event::PriceParser.parse(event.price)

      next record_unreadable(event) if result.nil?

      record_parsed(event, result)
    end

    Summary.new(considered: @considered, parsed: @parsed, pre_decimal: @pre_decimal,
                unreadable: @unreadable_counts.values.sum,
                unreadable_counts: @unreadable_counts, parsed_samples: @parsed_samples,
                applied: @apply)
  end

  private

  def record_pre_decimal
    @pre_decimal += 1
  end

  def record_unreadable(event)
    @unreadable_counts[event.price.to_s.strip] += 1
  end

  def record_parsed(event, result)
    @parsed += 1
    @parsed_samples[event.price.to_s.strip] ||= result.prices.map(&:to_price_string).join(" / ")

    return unless @apply

    event.update_columns(ticket_prices: result.prices.map(&:to_h), booking_fee: result.booking_fee)
  end
end
