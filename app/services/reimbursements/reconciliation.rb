require "csv"
require "bigdecimal"
require "digest"

module Reimbursements
  ##
  # Pure functions for reconciling EUSA "actuals" exports against expenses and
  # budgets — no Airtable/Rails dependencies. Ported from bedlam-bacs
  # `reconciliation.py`. The hardcoded F40 cost-centre filter there becomes the
  # +cost_centre_code+ argument here so each cost centre reconciles its own rows.
  #
  # `match_debit_to_expense` / `match_credit_to_budget` (which need the extended
  # Expense/Budget POROs) are ported alongside the model extension.
  module Reconciliation
    ##
    # One row from the EUSA actuals sheet.
    ActualsRow = Data.define(
      :nominal_code, :cost_centre, :ref, :date, :period,
      :narrative, :narrative_1, :debit, :credit, :net
    )

    ##
    # Two rows of a paste that cancel each other out (an accrual and its
    # reversal, a journal booked and re-booked), with the evidence score that
    # got them proposed.
    #
    # +key+ identifies the pair by each leg's CONTENT plus which occurrence of
    # that content it is (0 for the first row carrying it, 1 for the next, ...),
    # never by absolute position. Both halves matter:
    #
    # * the content digest is what survives the stateless wizard's re-parse on
    #   apply, and is unaffected by rows shifting position;
    # * the occurrence counter is what keeps two byte-identical pairs apart. A
    #   paste really can contain two separate £10 accruals and their two
    #   reversals; on a content-only key those collapse into one tickbox, so
    #   ticking one "votes for" the other and a genuine transaction is stamped
    #   as bookkeeping noise. A bare row index would separate them too, but it
    #   moves whenever anything earlier in the paste is added, removed or
    #   reordered, whereas an occurrence counter only moves when a row with
    #   IDENTICAL content is added or removed.
    #
    # If a key does fail to match on apply (the operator edited the textarea, or
    # a concurrent import changed what the dedup step drops), the pair reads as
    # unticked: both legs import as ordinary rows for a human to look at, which
    # is the safe direction. Inventing an offset is the unrecoverable mistake.
    OffsetPair = Data.define(:debit_row, :credit_row, :debit_index, :credit_index,
                             :debit_occurrence, :credit_occurrence, :score) do
      def key
        "#{Reconciliation.row_key(debit_row)}-#{debit_occurrence}" \
          "_#{Reconciliation.row_key(credit_row)}-#{credit_occurrence}"
      end
    end

    REQUIRED_COLUMNS = %i[nominal_code cost_centre date period narrative].freeze

    module_function

    # Parse pasted tab- or comma-separated actuals text into typed rows. Accepts
    # both the legacy 10-column layout and the Sage export (headers drive the
    # column mapping, so order/extra columns don't matter). Rows for a different
    # cost centre are dropped; rows with no cost centre are kept (some exports
    # omit it). Raises ArgumentError on missing columns or unparseable values.
    def parse_actuals_rows(text, cost_centre_code: "F40")
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
        cost_centre = cell.call(:cost_centre)
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

        # Keep only this cost centre's rows; blank cost centre is kept.
        next if cost_centre.present? && cost_centre.upcase != cost_centre_code.upcase

        rows << ActualsRow.new(
          nominal_code: cell.call(:nominal_code),
          cost_centre: cost_centre,
          ref: col_map.key?(:ref) ? cell.call(:ref) : "",
          date: parsed_date,
          period: cell.call(:period),
          narrative: cell.call(:narrative),
          narrative_1: col_map.key?(:narrative_1) ? cell.call(:narrative_1) : "",
          debit: debit,
          credit: credit,
          net: net
        )
      end

      rows
    end

    # Canonical key for deduplicating EUSA Actuals rows. Uses narrative (not date,
    # which timezone shifts can move) and normalises amounts so a zero BigDecimal,
    # an absent field (nil/""), and an Airtable-stored float all compare equal.
    def actuals_row_dedup_key(nominal_code, narrative, debit, credit)
      [ nominal_code.to_s, narrative.to_s.strip, norm_amount(debit), norm_amount(credit) ]
    end

    AMOUNT_TOLERANCE = BigDecimal("0.01")
    DATE_WINDOW_DAYS = 14

    # Best matching expense for a debit row: nominal code equal (case-insensitive),
    # amount within £0.01 (excl-VAT preferred, else gross), and either the
    # submitted-to-EUSA date or the payment-confirmed date within 14 days of the
    # row date. Returns the first match, or nil.
    # Two same-amount, same-nominal-code expenses submitted around the same
    # time are otherwise indistinguishable, so among every candidate that
    # matches, the one whose date is CLOSEST to the row's date wins — not
    # just whichever happens to come first in +expenses+ — narrowing (though
    # not eliminating) which specific record a genuine tie gets attributed to.
    def match_debit_to_expense(row, expenses)
      candidates = expenses.filter_map do |expense|
        next unless expense.effective_nominal_code.strip.casecmp?(row.nominal_code.strip)

        # A zero amount_excl_vat is the documented "not yet known" sentinel,
        # not a genuine zero — || alone doesn't fall back to the gross amount
        # for it, since 0/BigDecimal("0") are truthy in Ruby.
        excl_vat = expense.amount_excl_vat
        compare_amount = excl_vat.nil? || excl_vat.zero? ? expense.amount : excl_vat
        next if compare_amount.nil? || (compare_amount - row.debit).abs > AMOUNT_TOLERANCE

        candidate_dates = [ expense.submitted_to_eusa_date, expense.payment_confirmed_date ].compact
        closest = candidate_dates.map { |date| (date - row.date).abs }.select { |diff| diff <= DATE_WINDOW_DAYS }.min
        [ expense, closest ] if closest
      end
      candidates.min_by { |(_expense, distance)| distance }&.first
    end

    # Matching income budget for a credit row: nominal code equal
    # (case-insensitive). No amount/date match needed for income. First match or nil.
    def match_credit_to_budget(row, budgets)
      budgets.find { |budget| budget.nominal_code.strip.casecmp?(row.nominal_code.strip) }
    end

    # --- offsetting pairs --------------------------------------------------

    # Scoring weights, tuned against a real 309-row EUSA F40 export. Offset
    # legs there are overwhelmingly on the SAME nominal code (they are
    # accrual/reversal and re-booked journal pairs, not cross-code
    # reclassifications), but the reference only matches about half the time,
    # and legs routinely straddle months (a September accrual released in
    # October; one pair three months apart). So no single predicate can be a
    # hard filter: a genuine claim can collide by amount with an unrelated
    # reversal, and only weighing the evidence keeps the two apart.
    OFFSET_SCORE_SAME_REF = 4
    OFFSET_SCORE_SAME_NOMINAL = 2
    OFFSET_SCORE_SAME_PERIOD = 1
    OFFSET_SCORE_NARRATIVE_PREFIX = 1
    # A pair must reach this to be proposed at all: a reference match on its
    # own clears it, as does nominal + period + narrative agreement on the same
    # day. Anything weaker leaves BOTH rows in the working set rather than
    # guessing.
    OFFSET_MIN_SCORE = 4
    # Legs this far apart or less cost 1 point, further costs 2.
    OFFSET_NEAR_DATE_DAYS = 31
    # Narratives counted as agreeing when their normalised forms share this
    # many leading characters. In the real export the shared-prefix length is
    # bimodal (either 0 or 10+ characters), so anywhere in that gap behaves
    # identically; 8 sits in the middle of it.
    OFFSET_NARRATIVE_PREFIX_CHARS = 8
    # EUSA's financial year, and its accounting periods 1..12, run April to March.
    FINANCIAL_YEAR_START_MONTH = 4

    # Finds the offsetting pairs in a parsed paste. Returns
    # [pairs, remaining_rows]: +pairs+ are OffsetPairs ordered strongest
    # evidence first (what the preview shows for ticking), +remaining_rows+ is
    # every row that was NOT paired, in paste order, ready for the ordinary
    # debit->expense / credit->budget matching.
    #
    # Candidates are rows with an identical absolute amount (exact BigDecimal,
    # never a float), opposite signs, in the same financial year. Each is
    # scored, anything below OFFSET_MIN_SCORE is dropped, and the survivors are
    # taken greedily strongest-first so a row can only ever belong to one pair
    # and the best-evidenced claim on a leg wins.
    def detect_offsetting_pairs(rows)
      candidates = offset_candidates(rows)
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

    # For each row, how many EARLIER rows in the paste carry byte-identical
    # content: 0 for the first occurrence, 1 for the next, and so on. This is
    # what lets two duplicate pairs have two tickboxes (see OffsetPair#key).
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

    # The eligible pairs, strongest evidence first; ties break on paste order so
    # the result is deterministic. Rows are bucketed by absolute amount before
    # pairing, so a big paste doesn't pay for comparing every row with every
    # other one.
    def offset_candidates(rows)
      signed = rows.each_with_index.filter_map do |row, index|
        amount = row.debit - row.credit
        [ row, index, amount ] unless amount.zero?
      end

      candidates = []
      signed.group_by { |(_row, _index, amount)| amount.abs }.each_value do |bucket|
        next if bucket.size < 2

        bucket.combination(2) do |(row_a, index_a, amount_a), (row_b, index_b, amount_b)|
          next unless amount_a.negative? ^ amount_b.negative?
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

    # How much evidence says these two rows are the same transaction booked
    # both ways. See the OFFSET_SCORE_* constants for why each signal weighs
    # what it does.
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

    # An accrual and its reversal are usually the same narrative with one word
    # swapped part-way through ("PO 40000123 accrual ..." / "PO 40000123
    # reversal ..."), so the shared LEADING run is the signal, not equality.
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

      # BigDecimal (not Float) so the key is exact at every magnitude — a
      # float round-trip collapses distinct large amounts onto one key.
      # BigDecimal("0") renders "0.0", matching the nil/"" branch above — but
      # BigDecimal("-0.00") renders "-0.0", so a negative-zero value (an
      # Airtable formula or manual entry that preserves the sign) must be
      # normalised to the same key as an ordinary zero.
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
