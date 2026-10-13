module Climate
  ##
  # Parses a Govee Home CSV export into rows for ReadingIngest. A real one has a
  # UTF-8 BOM, sampling prose in the timestamp header and a stray space after the
  # first comma:
  #
  #   \xEF\xBB\xBFTimestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity
  #   2026-08-06 09:22:00,24.6,53.7
  #
  # The header names its own unit, so this reads it and REFUSES a file it cannot
  # identify rather than guessing.
  class CsvImport
    UNIT_CELSIUS = "C".freeze
    UNIT_FAHRENHEIT = "F".freeze

    # Matched against the temperature header, lowercased.
    UNIT_PATTERNS = { UNIT_CELSIUS => /celsius|centigrade|\(\s*c\s*\)|°\s*c\b/,
                      UNIT_FAHRENHEIT => /fahrenheit|\(\s*f\s*\)|°\s*f\b/ }.freeze

    MAX_ROWS = 200_000 # a 2-year export at 1-minute sampling is ~1M; refuse beyond sanity

    attr_reader :rows, :errors, :skipped, :unit

    def initialize(text)
      @rows = []
      @errors = []
      @skipped = []
      @unit = nil
      # dup first: force_encoding mutates its receiver and Graph hands back a
      # frozen string; the FrozenError would leave the message unread forever.
      parse(text.to_s.dup.force_encoding(Encoding::UTF_8))
    end

    def valid? = @errors.empty?

    private

    def parse(text)
      # The BOM would otherwise become part of the first header, so no column matches.
      body = text.delete_prefix("﻿").strip
      return @errors << "That file is empty." if body.blank?

      table = parse_table(body)
      return if table.nil?

      headers = table.shift.to_a.map { |cell| cell.to_s.strip }
      return unless locate_columns(headers)
      return @errors << "That file has more than #{MAX_ROWS} rows; split it into smaller exports." if table.size > MAX_ROWS

      # +2 so the reported number is the line an operator sees in an editor.
      table.each_with_index { |row, index| read_row(row, index + 2) }
      @errors << "That file has headers but no readings." if @rows.empty? && @errors.empty?
      @rows.sort_by! { |row| row[:recorded_at] }
    end

    def parse_table(body)
      first_line = body.each_line.first.to_s
      delimiter = first_line.count("\t") > first_line.count(",") ? "\t" : ","
      CSV.parse(body, col_sep: delimiter, skip_blanks: true)
    rescue CSV::MalformedCSVError => e
      @errors << "That file could not be read as CSV (#{e.message})."
      nil
    end

    def locate_columns(headers)
      @time_index = find_column(headers, %w[time date])
      @temp_index = find_column(headers, %w[temp])
      @humidity_index = find_column(headers, %w[humid])

      @errors << "No timestamp column found." if @time_index.nil?
      @errors << "No temperature column found." if @temp_index.nil?
      @errors << "No humidity column found." if @humidity_index.nil?
      return false if @errors.any?

      @unit = detect_unit(headers[@temp_index])
      if @unit.nil?
        @errors << "The temperature column (#{headers[@temp_index].inspect}) does not say which " \
                   "unit it is in. Export again with the app set to Celsius, or rename the " \
                   "column to include \"Celsius\" or \"Fahrenheit\". This importer will not guess."
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

    # Naive local wall-clock; parsing it as UTC shifts every reading an hour through BST.
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
