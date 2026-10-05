##
# Reads the free-text events.price column into TicketPrices.
#
# A wrong parse publishes a wrong price, while a refusal leaves the row as it is,
# so #parse returns nil unless every character is an amount, a band word or a
# separator.
#
# Pre-decimal prices are a trap: "2/6, 3/6, 5/-" is shillings and pence, not five
# prices, and a bare "5/6" on a 1962 show says nothing about itself. The real
# defence is the caller's date gate, decimal_era?.
##
class Event::PriceParser
  Result = Data.define(:prices, :booking_fee)

  DECIMALISATION_DATE = Date.new(1971, 2, 15).freeze

  # Exactly "free": "Free / donations" is pay-what-you-can, a different promise.
  FREE = /\A(?:free|free!|free\s+unticketed|0(?:\.00?)?)\z/i

  # Shillings and pence: "5/-", "4s", "6d".
  PRE_DECIMAL = %r{/\s*-|\d\s*[sd]\b}i

  AMOUNT = /£?\s*(\d+(?:\.\d{1,2})?)\s*(p\b)?/i

  # A word following its amount ("£6 concessions"). Words with no category of
  # their own become "other" and keep the word.
  BAND_WORDS = {
    "concession" => [ "concession", nil ], "concessions" => [ "concession", nil ],
    "conc" => [ "concession", nil ], "concs" => [ "concession", nil ],
    "member" => [ "member", nil ], "members" => [ "member", nil ],
    "full" => [ "standard", nil ], "standard" => [ "standard", nil ],
    "adult" => [ "standard", nil ], "adults" => [ "standard", nil ],
    "student" => [ "other", "Student" ], "students" => [ "other", "Student" ],
    "unwaged" => [ "other", "Unwaged" ]
  }.freeze

  # Words with no meaning beside a price, whether captured as a band word or left
  # in the residue.
  FILLER_WORDS = %w[price prices ticket tickets each and or].freeze
  FILLER = /\A(?:#{Regexp.union(FILLER_WORDS)})\z/i
  FILLER_IN_RESIDUE = /\b(?:#{Regexp.union(FILLER_WORDS)})\b/i

  # A closed list, most specific first: anything else after the prices is prose,
  # and prose is refused.
  FEE_SUFFIXES = [
    /\+\s*fees\s*,\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\s*on\s*the\s*door\.?\z/i,
    /\(\s*\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*on\s*the\s*door\s*\)\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\s*on\s*the\s*door\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*on\s*the\s*door\.?\z/i,
    /\+\s*fees\.?\z/i
  ].freeze

  # Bedlam is a 90-seat student theatre: "150" is £1.50 without the dot, and
  # "1/75" is £1.75 with a slash, not a 75x spread between two bands.
  MAX_PLAUSIBLE_AMOUNT = BigDecimal(100)
  MAX_BAND_RATIO = 10

  # Unnamed bands fill these, dearest first. A fourth unnamed amount has no
  # category left, so it is refused.
  UNNAMED_ORDER = %w[standard concession member].freeze

  class << self
    def parse(raw)
      text = raw.to_s.strip

      return nil if text.blank?
      return free_result if text.match?(FREE)
      return nil if text.match?(PRE_DECIMAL)

      text, booking_fee = strip_fee_clause(text)
      bands = scan_bands(text)

      return nil if bands.nil? || bands.empty?

      prices = assign_categories(bands)

      return nil if prices.nil? || implausible?(prices)

      Result.new(prices: prices, booking_fee: booking_fee)
    end

    # Before decimalisation prices are in shillings, and the string cannot always
    # say so.
    def decimal_era?(date)
      date.present? && date >= DECIMALISATION_DATE
    end

    private

    # Zero bands have no ratio: "0/1.50" is a real free-plus-paid pair.
    def implausible?(prices)
      amounts = prices.map(&:amount)

      return true if amounts.max > MAX_PLAUSIBLE_AMOUNT

      paid = amounts.reject(&:zero?)

      paid.any? && paid.max / paid.min > MAX_BAND_RATIO
    end

    def free_result
      Result.new(prices: [ Event::TicketPrice.new(category: "standard", amount: 0) ], booking_fee: nil)
    end

    def strip_fee_clause(text)
      FEE_SUFFIXES.each do |pattern|
        match = pattern.match(text)
        next if match.nil?

        return [ text[0...match.begin(0)].strip, match.captures.first&.to_d ]
      end

      [ text, nil ]
    end

    # Every amount with its band word, or nil if anything is left over: the
    # residue check refuses "£8 with a cocktail, £4 without".
    def scan_bands(text)
      residue = text.dup
      bands = []

      text.scan(/#{AMOUNT}\s*([A-Za-z]+)?/) do |amount, pence, word|
        band = band_for(amount, pence, word)

        return nil if band.nil?

        bands << band
        residue.sub!(Regexp.last_match(0), " ")
      end

      # Separators, brackets and filler are expected; a letter or digit is not.
      residue = residue.gsub(FILLER_IN_RESIDUE, " ").gsub(%r{[/,&()\s.\-]+}, " ").strip

      return nil unless residue.empty?

      bands
    end

    def band_for(amount, pence, word)
      value = amount.to_d
      value /= 100 if pence.present?

      return [ value, nil, nil ] if word.blank?

      named = BAND_WORDS[word.downcase]

      return [ value, named[0], named[1] ] if named

      # Anything but filler is prose, which the residue check cannot see once this
      # scan has consumed it.
      word.match?(FILLER) ? [ value, nil, nil ] : nil
    end

    # Named bands keep their name; the rest fill the unused categories by AMOUNT,
    # never position, since "3/4/5" and "£5.50/5/4.50" both occur.
    def assign_categories(bands)
      named, unnamed = bands.partition { |_, category, _| category.present? }

      taken = named.map { |_, category, _| category }

      return nil if taken.tally.any? { |category, count| count > 1 && category != "other" }

      available = UNNAMED_ORDER - taken

      return nil if unnamed.size > available.size

      assigned = unnamed.sort_by { |amount, _, _| -amount }
                        .each_with_index.map { |(amount, _, _), index| [ amount, available[index], nil ] }

      (named + assigned).sort_by { |amount, _, _| -amount }
                        .map { |amount, category, label| Event::TicketPrice.new(category: category, label: label, amount: amount) }
    end
  end
end
