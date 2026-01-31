# frozen_string_literal: true

##
# Service-like model for parsing user import data and categorizing rows.
# Not backed by a database table.
#
# Accepts either pasted TSV data or an uploaded xlsx file.
# Categorizes each row into buckets based on matching rules:
# - exact_match_id: User with matching student_id or associate_id
# - exact_match_email: User with matching email
# - fuzzy_match: Possible match by name (active users only)
# - create_new: No match found
#
# Used by both:
# - Bulk User Import (creates users without member role)
# - Bulk Show Crew Import (creates users + adds team membership)
##
class UserImport
  BUCKETS = %i[exact_match_id exact_match_email fuzzy_match create_new].freeze

  # Columns for user import: Name, Student/Associate ID (optional), Email (optional)
  USER_IMPORT_COLUMNS = [ "Name", "Student ID", "Email" ].freeze

  # Columns for show crew import: Name, Student/Associate ID (optional), Email (optional), Position
  CREW_IMPORT_COLUMNS = [ "Name", "Student ID", "Email", "Position" ].freeze

  attr_reader :rows, :categorized, :errors

  def initialize(data, input_type:, import_mode: :user)
    @errors = []
    @import_mode = import_mode
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

    # Email handling: use provided email, or auto-generate from student_id
    email = row["Email"].to_s.strip.downcase.presence
    if email.blank? && student_id.present?
      email = "#{student_id}@ed.ac.uk"
    end

    result = {
      original_name: name,
      first_name: name_parts[0].to_s,
      last_name: name_parts[1].to_s,
      email: email,
      student_id: student_id,
      associate_id: associate_id
    }

    # Add position for crew imports
    if @import_mode == :crew
      result[:position] = row["Position"].to_s.strip.presence
    end

    result
  end

  def categorize_rows
    result = BUCKETS.index_with { |_| [] }

    # For fuzzy matching, only consider "active" users (with recent team memberships)
    # Use the same threshold as the duplicates index
    @active_user_ids = active_user_ids_for_matching

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
      return [ :exact_match_id, user ] if user
    end

    # 2. Match by associate_id
    if row[:associate_id].present?
      user = User.find_by(associate_id: row[:associate_id])
      return [ :exact_match_id, user ] if user
    end

    # 3. Match by email
    if row[:email].present?
      user = User.find_by(email: row[:email])
      return [ :exact_match_email, user ] if user
    end

    # 4. Fuzzy name match (last name exact, first name fuzzy) - only for active users
    if row[:last_name].present?
      candidates = User.where(last_name: row[:last_name]).where(id: @active_user_ids)
      candidates.each do |user|
        next unless User.fuzzy_first_name_match?(row[:first_name], user.first_name)

        # Found a fuzzy match - propose for review
        return [ :fuzzy_match, user ]
      end
    end

    # 5. No match found - create new
    [ :create_new, nil ]
  end

  # Get IDs of users who have been active in recent events (team memberships).
  # Uses the same threshold as the duplicates index (current academic year + 3 years back).
  def active_user_ids_for_matching
    current_academic_year = ApplicationController.helpers.date_to_academic_year(Date.current)
    threshold_year = current_academic_year - 3

    # Convert academic years to actual date range (September of threshold year to now)
    threshold_date = Date.new(threshold_year, 9, 1)

    # Use unscoped to avoid default ORDER BY which conflicts with DISTINCT in MySQL
    TeamMember.unscoped
              .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
              .where(teamwork_type: "Event")
              .where("events.start_date >= ? OR events.end_date >= ?", threshold_date, threshold_date)
              .distinct
              .pluck(:user_id)
  end
end
