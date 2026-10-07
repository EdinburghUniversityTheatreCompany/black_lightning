# frozen_string_literal: true

# TSV paste and xlsx parsing for the import models. The includer implements normalize_row(row).
module ImportParsing
  extend ActiveSupport::Concern

  included do
    attr_reader :rows, :categorized, :errors
  end

  private

  # Canonical TSV for the stateless wizards, which carry an upload to apply in a hidden field. A
  # tab or newline inside a cell is escaped, or it shifts every later column when apply re-parses.

  ESCAPES = { "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n" }.freeze
  UNESCAPES = { "\\" => "\\", "t" => "\t", "n" => "\n" }.freeze

  # Block-form gsub: the string form would read a backslash in the replacement as a backreference.
  def escape_cell(value)
    value.to_s.delete("\r").gsub(/[\\\t\n]/) { |char| ESCAPES.fetch(char) }
  end

  def unescape_cell(value)
    value.to_s.gsub(/\\(.)/) { UNESCAPES.fetch(::Regexp.last_match(1), ::Regexp.last_match(0)) }
  end

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

    require "roo" # lazy: kept out of the boot heap (Gemfile require:false)
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

  # The header named `keyword` (any of lower, Capitalised, UPPER case), else the first header containing it.
  def find_column(row, keyword)
    row.values_at(keyword, keyword.capitalize, keyword.upcase).find(&:present?) ||
      row.find { |header, _| header.to_s.downcase.include?(keyword.downcase) }&.last
  end

  def parse_name(name_string)
    name = name_string.to_s.strip
    name_parts = name.split(/\s+/, 2)
    {
      original_name: name,
      first_name: name_parts[0].to_s,
      last_name: name_parts[1].to_s
    }
  end

  # "ID", "Student ID", "associate_id", "userid" and the like.
  ID_COLUMN_PATTERN = /\A(student|associate|user)?[\s_]*id\z/i

  # Reads the ID type off the value's format; at most one key is populated.
  def parse_any_id(raw)
    value = raw.to_s.strip
    result = { user_id: nil, student_id: nil, associate_id: nil }
    return result if value.blank?

    if value.match?(/\As\d{7}\z/i)
      result[:student_id] = value.downcase
    elsif value.match?(/\AASSOC\d+\z/i)
      result[:associate_id] = value.upcase
    else
      result[:user_id] = parse_user_id(value)
    end

    result
  end

  # Every ID-like column, the first value found winning per type.
  def collect_ids_from_row(row)
    merged = { user_id: nil, student_id: nil, associate_id: nil }

    row.each do |header, value|
      next unless header.to_s.strip.match?(ID_COLUMN_PATTERN)
      next if value.blank?

      parse_any_id(value).each do |key, val|
        merged[key] ||= val
      end
    end

    merged
  end

  # A positive integer or nil. Integer() rather than to_i, so a blank raises instead of reading 0.
  def parse_user_id(raw)
    id = Integer(raw.to_s.strip, 10)
    id.positive? ? id : nil
  rescue ArgumentError, TypeError
    nil
  end
end
