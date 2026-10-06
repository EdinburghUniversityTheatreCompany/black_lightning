require "csv"
require "bigdecimal"
require "digest"

module Reimbursements
  ##
  # Pure functions for reconciling EUSA "actuals" exports against expenses and budgets, with no
  # database access so they unit-test without one. Each parsed row carries its own cost-centre code;
  # deciding which centre it lands in is Reimbursements::ActualsAttribution's job.
  module Reconciliation
    ##
    # One row from the EUSA actuals sheet.
    ActualsRow = Data.define(
      :nominal_code, :cost_centre, :ref, :date, :period,
      :narrative, :narrative_1, :debit, :credit, :net
    )

    ##
    # Two rows of a paste that cancel out (an accrual and its reversal, a journal booked and re-booked),
    # with the evidence score that got them proposed.
    #
    # +key+ is each leg's CONTENT digest plus its occurrence number (0 for the first row carrying that
    # content, 1 for the next), never a position: the digest survives the stateless wizard's re-parse,
    # and the occurrence keeps two byte-identical pairs on two tickboxes. A key that fails to match on
    # apply reads as unticked and both legs import as ordinary rows, because inventing an offset is the
    # unrecoverable mistake.
    OffsetPair = Data.define(:debit_row, :credit_row, :debit_index, :credit_index,
                             :debit_occurrence, :credit_occurrence, :score) do
      def key
        "#{Reconciliation.row_key(debit_row)}-#{debit_occurrence}" \
          "_#{Reconciliation.row_key(credit_row)}-#{credit_occurrence}"
      end
    end

    # Cost Centre is deliberately not required: some exports omit the column, which gives rows with no
    # cost centre for an operator to assign, not a malformed paste.
    REQUIRED_COLUMNS = %i[nominal_code date period narrative].freeze

    module_function

    # Parses pasted tab- or comma-separated actuals text into typed rows. Accepts the legacy 10-column
    # layout and the Sage export (headers drive the column mapping). Raises ArgumentError on missing
    # columns or unparseable values. EVERY row comes back whatever cost centre it names: the parser
    # cannot know which codes are configured here, so attribution belongs to ActualsAttribution.
    def parse_actuals_rows(text)
      text = text.to_s.strip
      return [] if text.empty?

      first_line = text.each_line.map(&:strip).find(&:present?).to_s
      delimiter = first_line.include?("\t") ? "\t" : ","
      table = CSV.parse(text, col_sep: delimiter)
      return [] if table.empty?

      col_map = build_col_map(table.first)
      validate_col_map(col_map)
      min_required_col = col_map.values.max

      rows = []
      table.each_with_index do |row, i|
        next if i.zero? # header
        next if row.all? { |cell| cell.to_s.strip.empty? }

        if row.length <= min_required_col
          raise ArgumentError,
            "Row #{i + 1} has only #{row.length} columns (need at least #{min_required_col + 1})"
        end

        cell = ->(key) { row[col_map[key]].to_s.strip }
        cost_centre = col_map.key?(:cost_centre) ? cell.call(:cost_centre) : ""
        parsed_date = parse_british_date(cell.call(:date))

        if col_map.key?(:goods_value)
          goods = parse_amount(cell.call(:goods_value))
          debit = goods.positive? ? goods : BigDecimal(0)
          credit = goods.negative? ? -goods : BigDecimal(0)
          net = goods
        else
          debit = parse_amount(cell.call(:debit))
          credit = parse_amount(cell.call(:credit))
          net = parse_amount(cell.call(:net))
        end

        rows << ActualsRow.new(
          nominal_code: cell.call(:nominal_code),
          cost_centre: cost_centre,
          ref: col_map.key?(:ref) ? cell.call(:ref) : "",
          date: parsed_date,
          # Normalised where a pasted sheet becomes rows, so dedup and the pair period score compare
          # the spelling the ledger stores.
          period: normalise_period(cell.call(:period)),
          narrative: cell.call(:narrative),
          narrative_1: col_map.key?(:narrative_1) ? cell.call(:narrative_1) : "",
          debit: debit,
          credit: credit,
          net: net
        )
      end

      rows
    end

    # The one canonical spelling of an EUSA period: zero-padded to two digits, so "6" and "06" are one
    # month and "10" no longer sorts between "1" and "2". Only a purely numeric value of up to two digits
    # is touched (Sage's period 13 included); anything else ("P6", a date, blank) stays as the sheet
    # spelled it, since padding what we cannot read would be guessing. Idempotent, which is what lets it
    # sit on a before_validation, in the parser and in the backfill.
    def normalise_period(value)
      stripped = value.to_s.strip
      return stripped unless /\A\d+\z/.match?(stripped)

      number = stripped.to_i
      number <= 99 ? format("%02d", number) : stripped
    end

    # Canonical key for deduplicating EUSA Actuals rows. Narrative rather than date, which timezone
    # shifts can move; an absent amount compares equal to a zero one.
    def actuals_row_dedup_key(nominal_code, narrative, debit, credit)
      [ nominal_code.to_s, narrative.to_s.strip, norm_amount(debit), norm_amount(credit) ]
    end

    AMOUNT_TOLERANCE = BigDecimal("0.01")
    # International claims match on a PERCENTAGE window, not the penny one: the stored amount is
    # finance's GBP estimate and the actual is what EUSA's bank charged after the FX spread and fees,
    # pounds apart on a few hundred. 5% covers that and is far short of the gap between two different
    # payments. It is not widened for the UK rail: an unmatched row a human can see beats a wrong link
    # every rollup repeats.
    INTERNATIONAL_TOLERANCE_RATE = BigDecimal("0.05")
    DATE_WINDOW_DAYS = 14

    # Best expense for a debit row: nominal code equal (case-insensitive), amount within
    # amount_tolerance_for (excl-VAT preferred, else gross), and the submitted-to-EUSA or
    # payment-confirmed date within 14 days of the row. Of several candidates the one whose date is
    # CLOSEST wins, which narrows (not eliminates) where a genuine tie goes. Returns nil if nothing matches.
    def match_debit_to_expense(row, expenses)
      candidates = expenses.filter_map do |expense|
        next unless expense.effective_nominal_code.strip.casecmp?(row.nominal_code.strip)

        # 0 ex-VAT means "not yet known" (0 is truthy, so || alone would not fall back to gross).
        excl_vat = expense.amount_excl_vat
        compare_amount = excl_vat.nil? || excl_vat.zero? ? expense.amount : excl_vat
        next if compare_amount.nil? ||
                (compare_amount - row.debit).abs > amount_tolerance_for(expense, compare_amount)

        candidate_dates = [ expense.submitted_to_eusa_date, expense.payment_confirmed_date ].compact
        closest = candidate_dates.map { |date| (date - row.date).abs }.select { |diff| diff <= DATE_WINDOW_DAYS }.min
        [ expense, closest ] if closest
      end
      candidates.min_by { |(_expense, distance)| distance }&.first
    end

    # How far a row's amount may sit from the claim's. Read off the EXPENSE because nothing on the
    # actuals row says whether a payment went by BACS or SWIFT, and nothing needs to: each expense
    # knows its own rail. The percentage never narrows below the penny floor, or a small claim would
    # fail on a rounding difference.
    def amount_tolerance_for(expense, compare_amount)
      return AMOUNT_TOLERANCE unless expense.international?

      [ (compare_amount.abs * INTERNATIONAL_TOLERANCE_RATE), AMOUNT_TOLERANCE ].max
    end

    # First income budget with an equal nominal code (case-insensitive); income needs no amount or
    # date match.
    def match_credit_to_budget(row, budgets)
      budgets.find { |budget| budget.nominal_code.strip.casecmp?(row.nominal_code.strip) }
    end

    # --- offsetting pairs --------------------------------------------------

    # Scoring weights, tuned against a real 309-row EUSA F40 export, where the reference matches only
    # half the time and legs straddle months, so neither can be a hard filter. Same nominal code IS a
    # hard filter (offset_candidates) and still scores, so the score finance sees keeps its /8 scale.
    OFFSET_SCORE_SAME_REF = 4
    OFFSET_SCORE_SAME_NOMINAL = 2
    OFFSET_SCORE_SAME_PERIOD = 1
    OFFSET_SCORE_NARRATIVE_PREFIX = 1
    # A pair needs this to be proposed. Same nominal gives every candidate 2, so it must find 2 more:
    # a reference match (4, less the date penalty, so alone only same-day clears it) or, without one,
    # period plus narrative on the same day. Anything weaker leaves BOTH rows unpaired. Maximum is 8.
    OFFSET_MIN_SCORE = 4
    # Legs this far apart or less cost 1 point, further costs 2.
    OFFSET_NEAR_DATE_DAYS = 31
    # Narratives agree when their normalised forms share this many leading characters; in the real
    # export the shared-prefix length is bimodal (0 or 10+), so anywhere in the gap behaves the same.
    OFFSET_NARRATIVE_PREFIX_CHARS = 8
    # EUSA's financial year, and its accounting periods 1..12, run April to March.
    FINANCIAL_YEAR_START_MONTH = 4

    # Finds the offsetting pairs in a parsed paste. Returns [pairs, remaining_rows]: OffsetPairs
    # strongest evidence first (the order the preview shows for ticking), and every unpaired row in
    # paste order.
    #
    # Candidates have an identical absolute amount (exact BigDecimal), opposite signs, and the same
    # nominal code, cost centre and financial year. Each is scored, those below OFFSET_MIN_SCORE are
    # dropped, and the rest taken greedily strongest-first so a row belongs to at most one pair.
    #
    # +cost_centres+ is an optional array of identity strings parallel to +rows+, for a caller that has
    # resolved each row's attribution (a blank-code row assigned by hand belongs to the pot chosen).
    # Omitted, each row's exported code is used and a blank agrees with nothing.
    def detect_offsetting_pairs(rows, cost_centres: nil)
      candidates = offset_candidates(rows, cost_centres || rows.map(&:cost_centre))
      occurrences = row_occurrences(rows)
      consumed = Set.new
      pairs = []

      candidates.each do |score, debit, credit|
        next if consumed.include?(debit.last) || consumed.include?(credit.last)

        consumed << debit.last << credit.last
        pairs << OffsetPair.new(debit_row: debit.first, credit_row: credit.first,
                                debit_index: debit.last, credit_index: credit.last,
                                debit_occurrence: occurrences[debit.last],
                                credit_occurrence: occurrences[credit.last],
                                score: score)
      end

      remaining = rows.each_with_index.reject { |_row, index| consumed.include?(index) }.map(&:first)
      [ pairs, remaining ]
    end

    # Content digest identifying one parsed row, stable across re-parses of the
    # same paste and independent of its position (see OffsetPair#key).
    def row_key(row)
      fields = [ row.nominal_code, row.cost_centre, row.ref, row.date, row.period,
                 row.narrative, row.narrative_1, row.debit, row.credit, row.net ]
      Digest::SHA256.hexdigest(fields.map(&:to_s).join(""))[0, 12]
    end

    # How many EARLIER rows carry byte-identical content, so duplicate pairs get distinct tickboxes
    # (see OffsetPair#key).
    def row_occurrences(rows)
      seen = Hash.new(0)
      rows.map do |row|
        key = row_key(row)
        count = seen[key]
        seen[key] = count + 1
        count
      end
    end
    private_class_method :row_occurrences

    # The eligible pairs, strongest first, ties by paste order. Rows are bucketed by absolute amount so
    # a big paste doesn't compare every row with every other.
    def offset_candidates(rows, cost_centre_keys)
      signed = rows.each_with_index.filter_map do |row, index|
        amount = row.debit - row.credit
        [ row, index, amount ] unless amount.zero?
      end

      candidates = []
      signed.group_by { |(_row, _index, amount)| amount.abs }.each_value do |bucket|
        next if bucket.size < 2

        bucket.combination(2) do |(row_a, index_a, amount_a), (row_b, index_b, amount_b)|
          next unless amount_a.negative? ^ amount_b.negative?
          # Same nominal code is a HARD requirement, not just 2 points: a Sage payment-run ref is stamped
          # across a whole run, so ref + period on one day would pair a cost with unrelated income of the
          # same size and hide it from every rollup. Genuine pairs were same-nominal anyway. Blank codes
          # never pair.
          next unless same_field?(row_a.nominal_code, row_b.nominal_code)
          # Same cost centre, for the same reason: two pots' unrelated transactions must never cancel
          # and hide real spend from both rollups.
          next unless same_field?(cost_centre_keys[index_a], cost_centre_keys[index_b])
          next unless same_financial_year?(row_a.date, row_b.date)

          score = offset_pair_score(row_a, row_b)
          next if score < OFFSET_MIN_SCORE

          debit, credit = amount_a.positive? ? [ [ row_a, index_a ], [ row_b, index_b ] ]
                                             : [ [ row_b, index_b ], [ row_a, index_a ] ]
          candidates << [ score, debit, credit ]
        end
      end

      candidates.sort_by { |score, debit, credit| [ -score, debit.last, credit.last ] }
    end
    private_class_method :offset_candidates

    # Evidence that two rows are one transaction booked both ways; see the OFFSET_SCORE_* constants.
    def offset_pair_score(row_a, row_b)
      score = 0
      score += OFFSET_SCORE_SAME_REF if same_field?(row_a.ref, row_b.ref)
      score += OFFSET_SCORE_SAME_NOMINAL if same_field?(row_a.nominal_code, row_b.nominal_code)
      score += OFFSET_SCORE_SAME_PERIOD if same_field?(row_a.period, row_b.period)
      if narrative_prefix_similar?(row_a.narrative, row_b.narrative)
        score += OFFSET_SCORE_NARRATIVE_PREFIX
      end
      score - offset_date_penalty(row_a.date, row_b.date)
    end
    private_class_method :offset_pair_score

    # Two blank fields agree on nothing, so a blank never scores.
    def same_field?(left, right)
      left = left.to_s.strip
      right = right.to_s.strip
      left.present? && left.casecmp?(right)
    end
    private_class_method :same_field?

    def offset_date_penalty(left, right)
      gap = (left - right).abs.to_i
      return 0 if gap.zero?

      gap <= OFFSET_NEAR_DATE_DAYS ? 1 : 2
    end
    private_class_method :offset_date_penalty

    def same_financial_year?(left, right)
      financial_year_start_year(left) == financial_year_start_year(right)
    end
    private_class_method :same_financial_year?

    def financial_year_start_year(date)
      date.month >= FINANCIAL_YEAR_START_MONTH ? date.year : date.year - 1
    end
    private_class_method :financial_year_start_year

    # An accrual and its reversal share a narrative with one word swapped part-way ("PO 40000123
    # accrual" / "PO 40000123 reversal"), so the shared LEADING run is the signal, not equality.
    def narrative_prefix_similar?(left, right)
      left = normalise_narrative(left)
      right = normalise_narrative(right)
      return false if left.length < OFFSET_NARRATIVE_PREFIX_CHARS ||
        right.length < OFFSET_NARRATIVE_PREFIX_CHARS

      common_prefix_length(left, right) >= OFFSET_NARRATIVE_PREFIX_CHARS
    end
    private_class_method :narrative_prefix_similar?

    def normalise_narrative(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end
    private_class_method :normalise_narrative

    def common_prefix_length(left, right)
      length = 0
      length += 1 while length < [ left.length, right.length ].min && left[length] == right[length]
      length
    end
    private_class_method :common_prefix_length

    # --- private helpers ---------------------------------------------------

    def norm_amount(value)
      return "0.0" if value.nil? || value == ""

      # BigDecimal not Float, so the key is exact at every magnitude. BigDecimal("-0.00") renders
      # "-0.0", so a negative zero is normalised to the same key as an ordinary zero.
      amount = BigDecimal(value.to_s)
      amount.zero? ? "0.0" : amount.to_s("F")
    rescue ArgumentError, TypeError
      "0.0"
    end
    private_class_method :norm_amount

    def normalise_header(header)
      header.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
    private_class_method :normalise_header

    def build_col_map(header_row)
      col_map = {}
      header_row.each_with_index do |raw, idx|
        header = normalise_header(raw)
        next if header.empty?

        key = column_key_for(header)
        col_map[key] = idx if key && !col_map.key?(key) # first occurrence wins
      end
      col_map
    end
    private_class_method :build_col_map

    def column_key_for(header)
      case header
      when "nominal" then :nominal_code
      when ->(h) { h.end_with?("accountnumber") } then :nominal_code
      when ->(h) { h.include?("costcentre") || (h.include?("cost") && h.include?("centre")) } then :cost_centre
      when ->(h) { h.include?("goodsvalue") } then :goods_value
      when ->(h) { h.include?("transactiondate") }, "date" then :date
      when ->(h) { h.include?("period") } then :period
      when ->(h) { h.include?("narrative") && h.include?("1") } then :narrative_1
      when ->(h) { h.include?("narrative") } then :narrative
      when ->(h) { h.include?("reference") }, "ref" then :ref
      when "debit" then :debit
      when "credit" then :credit
      when "net" then :net
      end
    end
    private_class_method :column_key_for

    def validate_col_map(col_map)
      missing = REQUIRED_COLUMNS - col_map.keys
      if missing.any?
        raise ArgumentError, "Header is missing required columns: #{missing.sort.join(', ')}"
      end

      has_amount = col_map.key?(:goods_value) ||
        (col_map.key?(:debit) && col_map.key?(:credit) && col_map.key?(:net))
      return if has_amount

      raise ArgumentError, "Header must contain either a GoodsValue column or Debit/Credit/Net columns"
    end
    private_class_method :validate_col_map

    # DD/MM/YYYY (British), falling back to ISO 8601. Base-10 Integer parse so a
    # leading-zero day/month isn't read as octal.
    def parse_british_date(value)
      value = value.to_s.strip
      parts = value.split("/")
      if parts.length == 3 && parts[2].match?(/\A\d{4}\z/)
        begin
          return Date.new(Integer(parts[2], 10), Integer(parts[1], 10), Integer(parts[0], 10))
        rescue ArgumentError # includes Date::Error; fall through to ISO
        end
      end

      begin
        return Date.iso8601(value[0, 10])
      rescue ArgumentError, Date::Error # fall through to raise below
      end

      raise ArgumentError, "Cannot parse date: #{value.inspect}"
    end
    private_class_method :parse_british_date

    def parse_amount(value)
      cleaned = value.to_s.strip.delete(",")
      return BigDecimal(0) if cleaned.empty?

      BigDecimal(cleaned)
    rescue ArgumentError
      raise ArgumentError, "Cannot parse amount: #{value.inspect}"
    end
    private_class_method :parse_amount
  end
end
