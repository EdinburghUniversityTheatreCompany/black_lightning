# frozen_string_literal: true

##
# Service-like model for parsing membership import data and categorizing rows.
# Not backed by a database table.
#
# Accepts either pasted TSV data or an uploaded xlsx file.
# Categorizes each row into one of five buckets based on matching rules.
##
class MembershipImport
  BUCKETS = %i[already_active activate_by_id activate_by_email propose_merge create_new].freeze

  attr_reader :rows, :categorized, :errors

  def initialize(data, input_type:)
    @errors = []
    @rows = parse_data(data, input_type)
    @categorized = categorize_rows
  end

  def valid?
    @errors.empty? && @rows.any?
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

  def normalize_row(row)
    # Parse "Name" into first_name and last_name
    name = row["Name"].to_s.strip
    name_parts = name.split(/\s+/, 2)

    # Extract student_id or associate_id from "Student ID" column
    raw_id = row["Student ID"].to_s.strip
    student_id = raw_id.match?(/\As\d{7}\z/i) ? raw_id.downcase : nil
    associate_id = raw_id.match?(/\AASSOC\d+\z/i) ? raw_id.upcase : nil

    {
      original_name: name,
      first_name: name_parts[0].to_s,
      last_name: name_parts[1].to_s,
      email: row["Purchaser Email"].to_s.strip.downcase.presence,
      student_id: student_id,
      associate_id: associate_id,
      member_type: row["Member Type"].to_s.strip.presence,
      date_purchased: parse_date(row["Date Purchased"])
    }
  end

  def parse_date(date_str)
    return nil if date_str.blank?

    Chronic.parse(date_str.to_s)&.to_date
  rescue StandardError
    nil
  end

  def categorize_rows
    result = BUCKETS.index_with { |_| [] }

    @rows.each_with_index do |row, index|
      bucket, match = determine_bucket(row)
      result[bucket] << { row: row, existing_user: match, index: index }
    end

    result
  end

  def determine_bucket(row)
    # 1. Match by student_id
    if row[:student_id].present?
      user = User.find_by(student_id: row[:student_id])
      if user
        return user.has_role?(:member) ? [ :already_active, user ] : [ :activate_by_id, user ]
      end
    end

    # 2. Match by associate_id
    if row[:associate_id].present?
      user = User.find_by(associate_id: row[:associate_id])
      if user
        return user.has_role?(:member) ? [ :already_active, user ] : [ :activate_by_id, user ]
      end
    end

    # 3. Match by email
    if row[:email].present?
      user = User.find_by(email: row[:email])
      if user
        return user.has_role?(:member) ? [ :already_active, user ] : [ :activate_by_email, user ]
      end
    end

    # 4. Fuzzy name match (last name exact, first name fuzzy)
    if row[:last_name].present?
      candidates = User.where(last_name: row[:last_name])
      candidates.each do |user|
        next unless User.fuzzy_first_name_match?(row[:first_name], user.first_name)

        # Found a fuzzy match - propose merge
        return [ :propose_merge, user ]
      end
    end

    # 5. No match found - create new
    [ :create_new, nil ]
  end
end
