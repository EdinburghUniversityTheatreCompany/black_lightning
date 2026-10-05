##
# Reads events.price into ticket_prices for every row the parser can read
# completely. Dry by default; check the report's refusals before APPLY=1.
#
# update_columns, so only ticket_prices and booking_fee move and the archive
# keeps rendering the price text it has today.
##
class Event::TicketPriceBackfill
  Summary = Data.define(:considered, :parsed, :pre_decimal, :unreadable,
                        :unreadable_counts, :parsed_samples, :applied)

  # Rows with bands already are skipped, so a re-run cannot overwrite bands a
  # producer typed.
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
