module Climate
  ##
  # Parses a Govee Home CSV export into rows for ReadingIngest.
  #
  # A real export looks like this — note the UTF-8 BOM, the sampling prose baked
  # into the timestamp header, and the stray space after the first comma:
  #
  #   \xEF\xBB\xBFTimestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity
  #   2026-08-06 09:22:00,24.6,53.7
  #
  # The header names its own unit — whatever the app is set to display — so this
  # reads it rather than assuming, and REFUSES a file it cannot identify. That
  # refusal replaced the old verify-the-unit-per-sensor flow.
  #
  # Pure parsing: no database, no dew point, no dedup. Dedup belongs to the
  # unique index, which is why re-importing an overlapping export is harmless.
  class CsvImport
    UNIT_CELSIUS = "C".freeze
    UNIT_FAHRENHEIT = "F".freeze

    # Matched against the temperature header, lowercased.
    UNIT_PATTERNS = { UNIT_CELSIUS => /celsius|centigrade|\(\s*c\s*\)|°\s*c\b/,
                      UNIT_FAHRENHEIT => /fahrenheit|\(\s*f\s*\)|°\s*f\b/ }.freeze

    TIMESTAMP_KEYWORDS = %w[timestamp time date].freeze
    TEMPERATURE_KEYWORDS = %w[temp].freeze
    HUMIDITY_KEYWORDS = %w[humid].freeze

    MAX_ROWS = 200_000 # a 2-year export at 1-minute sampling is ~1M; refuse beyond sanity

    attr_reader :rows, :errors, :skipped, :unit

    def initialize(text)
      @rows = []
      @errors = []
      @skipped = []
      @unit = nil
      parse(text.to_s)
    end

    def valid? = @errors.empty? && @rows.any?

    def range
      return nil if @rows.empty?

      @rows.first[:recorded_at]..@rows.last[:recorded_at]
    end

    private

    def parse(text)
      # The BOM would otherwise become part of the first header, so no column
      # matches and the file reads as structureless.
      body = text.delete_prefix("﻿").strip
      return @errors << "That file is empty." if body.blank?

      table = parse_table(body)
      return if table.nil?

      headers = table.shift.to_a.map { |cell| cell.to_s.strip }
      return unless locate_columns(headers)

      # +2 so the reported number is the line an operator sees in an editor.
      table.each_with_index { |row, index| read_row(row, index + 2) }
      @errors << "That file has headers but no readings." if @rows.empty? && @errors.empty?
      @rows.sort_by! { |row| row[:recorded_at] }
    end

    def parse_table(body)
      first_line = body.each_line.first.to_s
      delimiter = first_line.count("\t") > first_line.count(",") ? "\t" : ","
      table = CSV.parse(body, col_sep: delimiter, skip_blanks: true)
      return table if table.size > 1

      @errors << "That file has headers but no readings."
      nil
    rescue CSV::MalformedCSVError => e
      @errors << "That file could not be read as CSV (#{e.message})."
      nil
    end

    def locate_columns(headers)
      @time_index = find_column(headers, TIMESTAMP_KEYWORDS)
      @temp_index = find_column(headers, TEMPERATURE_KEYWORDS)
      @humidity_index = find_column(headers, HUMIDITY_KEYWORDS)

      @errors << "No timestamp column found." if @time_index.nil?
      @errors << "No temperature column found." if @temp_index.nil?
      @errors << "No humidity column found." if @humidity_index.nil?
      return false if @errors.any?

      @unit = detect_unit(headers[@temp_index])
      if @unit.nil?
        @errors << "The temperature column (#{headers[@temp_index].inspect}) does not say which " \
                   "unit it is in. Export again with the app set to Celsius, or rename the " \
                   "column to include \"Celsius\" or \"Fahrenheit\" — this importer will not guess."
      end

      @errors.empty?
    end

    def find_column(headers, keywords)
      headers.index { |header| keywords.any? { |keyword| header.downcase.include?(keyword) } }
    end

    def detect_unit(header)
      down = header.to_s.downcase
      UNIT_PATTERNS.find { |_unit, pattern| down.match?(pattern) }&.first
    end

    def read_row(row, line_number)
      return if row.compact.empty?

      if @rows.size >= MAX_ROWS
        @errors << "That file has more than #{MAX_ROWS} rows; split it into smaller exports."
        return
      end

      recorded_at = parse_time(row[@time_index])
      temperature = parse_number(row[@temp_index])
      humidity = parse_number(row[@humidity_index])

      if recorded_at.nil? || temperature.nil? || humidity.nil?
        return @skipped << "Line #{line_number}: #{row.compact.join(', ').truncate(80)}"
      end

      @rows << { recorded_at: recorded_at,
                 temperature_c: to_celsius(temperature),
                 relative_humidity: humidity,
                 raw_temperature: temperature,
                 raw_temperature_unit: @unit }
    end

    # Naive local wall-clock in the export; parsing it as UTC would shift every
    # reading an hour through BST.
    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def parse_number(value)
      return nil if value.blank?

      Float(value.to_s.strip)
    rescue ArgumentError, TypeError
      nil
    end

    def to_celsius(value)
      return value.round(2) if @unit == UNIT_CELSIUS

      ((value - 32.0) * 5.0 / 9.0).round(2)
    end
  end
end
