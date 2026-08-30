##
# Reads the free-text +events.price+ column into structured TicketPrices.
#
# Designed against the real production distribution, read 2026-08-30: 2742 events
# carry a price, in 461 distinct strings across 178 shapes.
#
# THE GOVERNING ASYMMETRY: a wrong parse writes a wrong price into structured
# data that search engines then publish, while a refusal leaves the row exactly
# as it is today. Prefer refusing to guessing. #parse returns nil for anything it
# cannot read completely, and "completely" is enforced by the residue check --
# every character has to be accounted for as an amount, a band name or a
# separator, or the whole string is refused.
#
# THE PRE-DECIMAL TRAP: 66 archive rows are in shillings and pence, year range
# 1893-1970. "2/6, 3/6, 5/-" is 2s6d, 3s6d and 5s -- not five prices of £2, £6,
# £3, £6 and £5, which is what a split on "/" reads, and which looks entirely
# plausible in the output. The markers below catch the obvious ones, but a bare
# "5/6" on a 1962 show says nothing about itself. The real defence is the caller's
# date gate (see the backfill task): nothing before decimalisation, 15 Feb 1971.
##
class Event::PriceParser
  Result = Data.define(:prices, :booking_fee)

  DECIMALISATION_DATE = Date.new(1971, 2, 15).freeze

  # Exactly "free", optionally exclaimed or qualified as unticketed. Anything
  # else attached ("Free / donations") is pay-what-you-can, a different promise.
  FREE = /\A(?:free|free!|free\s+unticketed|0(?:\.00?)?)\z/i

  # Shillings and pence: a solidus with no pence ("5/-"), or a figure suffixed
  # with the shilling or penny mark ("4s", "6d").
  PRE_DECIMAL = %r{/\s*-|\d\s*[sd]\b}i

  # An amount, with optional currency mark and an optional decimal pence suffix.
  AMOUNT = /£?\s*(\d+(?:\.\d{1,2})?)\s*(p\b)?/i

  # A band name may follow its amount ("£6 concessions") or precede nothing at
  # all. Words we do not have a category for become "other" and keep the word.
  BAND_WORDS = {
    "concession" => [ "concession", nil ], "concessions" => [ "concession", nil ],
    "conc" => [ "concession", nil ], "concs" => [ "concession", nil ],
    "member" => [ "member", nil ], "members" => [ "member", nil ],
    "full" => [ "standard", nil ], "standard" => [ "standard", nil ],
    "adult" => [ "standard", nil ], "adults" => [ "standard", nil ],
    "student" => [ "other", "Student" ], "students" => [ "other", "Student" ],
    "unwaged" => [ "other", "Unwaged" ]
  }.freeze

  # Words that carry no meaning of their own beside a price and may be discarded,
  # whether they were captured as a band word ("£12 full price") or left in the
  # residue by an amount that already claimed the word before them.
  FILLER_WORDS = %w[price prices ticket tickets each and or].freeze
  FILLER = /\A(?:#{Regexp.union(FILLER_WORDS)})\z/i
  FILLER_IN_RESIDUE = /\b(?:#{Regexp.union(FILLER_WORDS)})\b/i

  # The fee clauses that actually occur, most specific first. A closed list on
  # purpose: anything else trailing the prices is prose, and prose means refuse.
  FEE_SUFFIXES = [
    /\+\s*fees\s*,\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\s*on\s*the\s*door\.?\z/i,
    /\(\s*\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*on\s*the\s*door\s*\)\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\s*on\s*the\s*door\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*booking\s*fee\.?\z/i,
    /\+\s*£?\s*(\d+(?:\.\d{1,2})?)\s*on\s*the\s*door\.?\z/i,
    /\+\s*fees\.?\z/i
  ].freeze

  # Plausibility guards, both found by sweeping the real parses rather than
  # guessed at. Bedlam is a 90-seat student theatre: "150" is £1.50 typed without
  # the dot, not a £150 ticket, and "1/75" is £1.75 typed with a slash rather than
  # a 75x spread between two bands. Both read as confident, ordinary output, which
  # is what makes them worth refusing.
  MAX_PLAUSIBLE_AMOUNT = BigDecimal(100)
  MAX_BAND_RATIO = 10

  # Unnamed bands fill these in order, dearest first. Three is the ceiling: with
  # a fourth amount and nothing naming it there is no category left to give it,
  # and inventing one is the failure this parser exists to avoid.
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

    # Whether a row is even a candidate. Everything before decimalisation is
    # refused outright: those prices are in shillings and the string cannot
    # always say so.
    def decimal_era?(date)
      date.present? && date >= DECIMALISATION_DATE
    end

    private

    ##
    # A price we are not willing to publish. Zero bands are excluded from the
    # ratio: a free-plus-paid pair is a real thing ("0/1.50") and has no ratio.
    ##
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

    ##
    # Every amount in the string, each with the band word attached to it if there
    # is one. Returns nil the moment anything is left unaccounted for -- that
    # residue check is what stops "£8 with a cocktail, £4 without" being read as
    # a two-band price.
    ##
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

      # A filler word beside a price is harmless; anything else is prose, and the
      # residue check would not see it because it was consumed by this scan.
      word.match?(FILLER) ? [ value, nil, nil ] : nil
    end

    ##
    # Named bands keep their name; the rest fill the unused categories dearest
    # first. Assignment is by AMOUNT, never by position -- "3/4/5" and "7/8/10"
    # are both ascending in the archive while "£5.50/5/4.50" is descending, and
    # ranking by amount reads all three correctly with one rule.
    ##
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
