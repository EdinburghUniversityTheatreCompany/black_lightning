require "csv"
require "bigdecimal"

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
    def match_debit_to_expense(row, expenses)
      expenses.find do |expense|
        next false unless expense.effective_nominal_code.strip.casecmp?(row.nominal_code.strip)

        compare_amount = expense.amount_excl_vat || expense.amount
        next false if compare_amount.nil? || (compare_amount - row.debit).abs > AMOUNT_TOLERANCE

        candidate_dates = [ expense.submitted_to_eusa_date, expense.payment_confirmed_date ].compact
        next false if candidate_dates.empty?

        candidate_dates.any? { |date| (date - row.date).abs <= DATE_WINDOW_DAYS }
      end
    end

    # Matching income budget for a credit row: nominal code equal
    # (case-insensitive). No amount/date match needed for income. First match or nil.
    def match_credit_to_budget(row, budgets)
      budgets.find { |budget| budget.nominal_code.strip.casecmp?(row.nominal_code.strip) }
    end

    # --- private helpers ---------------------------------------------------

    def norm_amount(value)
      return "0.0" if value.nil? || value == ""

      Float(value).to_s
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
      if parts.length == 3
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
