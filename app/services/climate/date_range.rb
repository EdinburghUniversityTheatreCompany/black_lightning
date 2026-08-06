module Climate
  ##
  # The dashboard's URL state: +?from=2026-08-01&to=2026-08-06+, readable ISO
  # dates rather than an opaque token, per the project's URL-as-state rule.
  #
  # An unusable range is clamped and SAID SO (the controller flashes +notice+)
  # rather than silently rendering a different range as though it were the one
  # asked for — the same discipline as the reimbursements financial-year
  # selector falling back to the active year.
  class DateRange
    DEFAULT_DAYS = 7
    MAX_DAYS = 366

    attr_reader :from, :to, :notice

    # Parses ?from= / ?to=. Either may be absent: a bare /admin/climate means
    # the last week, and that default is deliberately NOT written back into the
    # URL, so the clean link keeps meaning "recent" while the preset links emit
    # explicit dates and keep meaning the same thing tomorrow.
    def self.from_params(params)
      to = parse_date(params[:to]) || Date.current
      from = parse_date(params[:from]) || (to - (DEFAULT_DAYS - 1).days)
      new(from: from, to: to, requested: { from: params[:from], to: params[:to] })
    end

    def self.parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
    private_class_method :parse_date

    def initialize(from:, to:, requested: {})
      @notice = nil
      @from, @to = clamp(from, to)
      note_unparseable(requested)
    end

    # Inclusive of the whole end day: someone asking for "to 6 August" means up
    # to the end of the 6th, not midnight at its start.
    def starts_at = from.beginning_of_day.in_time_zone
    def ends_at = to.end_of_day.in_time_zone
    def days = (to - from).to_i + 1
    def duration = ends_at - starts_at

    def to_param = { from: from.iso8601, to: to.iso8601 }
    def as_json(*) = { from: from.iso8601, to: to.iso8601 }

    private

    def clamp(from, to)
      if from > to
        @notice = "Those dates were the wrong way round, so they have been swapped."
        from, to = to, from
      end

      if (to - from).to_i + 1 > MAX_DAYS
        @notice = "That range was longer than a year, so it has been trimmed to the most recent #{MAX_DAYS} days."
        from = to - (MAX_DAYS - 1).days
      end

      [ from, to ]
    end

    def note_unparseable(requested)
      return if @notice.present?
      return unless requested.values.any? { |value| value.present? && self.class.send(:parse_date, value).nil? }

      @notice = "That date could not be read, so the default range is shown instead."
    end
  end
end
