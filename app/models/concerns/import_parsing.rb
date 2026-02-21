# frozen_string_literal: true

##
# Shared parsing functionality for import models.
# Handles TSV paste data and xlsx file uploads.
#
# Including class must implement:
# - normalize_row(row) - Convert raw row hash to normalized format
##
module ImportParsing
  extend ActiveSupport::Concern

  included do
    attr_reader :rows, :categorized, :errors
  end

  private

  def parse_data(data, input_type)
    case input_type
    when :paste
      parse_tsv(data)
    when :xlsx
      parse_xlsx(data)
    else
      @errors << "Unknown input type: #{input_type}"
      []
    end
  rescue StandardError => e
    @errors << "Failed to parse data: #{e.message}"
    []
  end

  def parse_tsv(data)
    return [] if data.blank?

    lines = data.strip.split("\n")
    return [] if lines.size < 2 # Need at least header + 1 row

    headers = lines.first.split("\t").map(&:strip)

    lines[1..].filter_map do |line|
      next if line.blank?

      values = line.split("\t").map(&:strip)
      row = headers.zip(values).to_h
      normalize_row(row)
    end
  end

  def parse_xlsx(file)
    return [] if file.blank?

    xlsx = Roo::Spreadsheet.open(file.path)
    sheet = xlsx.sheet(0)
    return [] if sheet.last_row.nil? || sheet.last_row < 2

    headers = sheet.row(1).map { |h| h.to_s.strip }

    (2..sheet.last_row).filter_map do |i|
      row_values = sheet.row(i)
      next if row_values.all?(&:blank?)

      row = headers.zip(row_values.map { |v| v.to_s.strip }).to_h
      normalize_row(row)
    end
  end

  # Find column value by looking for headers containing any of the keywords (case-insensitive)
  # Shared helper for flexible column name matching
  def find_column(row, *keywords)
    # First try exact matches for common variations
    keywords.each do |keyword|
      return row[keyword] if row[keyword].present?
      return row[keyword.capitalize] if row[keyword.capitalize].present?
      return row[keyword.upcase] if row[keyword.upcase].present?
    end

    # Fallback: find first column whose header contains ALL keywords
    matching_key = row.keys.find do |k|
      header = k.to_s.downcase
      keywords.all? { |kw| header.include?(kw.downcase) }
    end
    row[matching_key] if matching_key
  end

  # Parse name into first and last name parts
  def parse_name(name_string)
    name = name_string.to_s.strip
    name_parts = name.split(/\s+/, 2)
    {
      original_name: name,
      first_name: name_parts[0].to_s,
      last_name: name_parts[1].to_s
    }
  end

  # Parse database primary key from raw string. Returns a positive integer or nil.
  # Uses Integer() rather than to_i so blank strings raise rather than returning 0.
  def parse_user_id(raw)
    id = Integer(raw.to_s.strip, 10)
    id.positive? ? id : nil
  rescue ArgumentError, TypeError
    nil
  end

  # Parse student_id or associate_id from raw ID string
  def parse_id(raw_id)
    id = raw_id.to_s.strip
    student_id = id.match?(/\As\d{7}\z/i) ? id.downcase : nil
    associate_id = id.match?(/\AASSOC\d+\z/i) ? id.upcase : nil
    { student_id: student_id, associate_id: associate_id }
  end
end
