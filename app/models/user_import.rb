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
  include ImportParsing

  BUCKETS = %i[exact_match_id exact_match_email fuzzy_match create_new].freeze

  def initialize(data, input_type:, import_mode: :user)
    @errors = []
    @import_mode = import_mode
    @rows = parse_data(data, input_type)
    validate_rows
    @categorized = categorize_rows
  end

  def valid?
    @errors.empty? && @rows.any?
  end

  private

  def validate_rows
    return if @rows.empty?

    # For crew imports, validate that position column exists and has data
    if @import_mode == :crew
      rows_without_position = @rows.select { |row| row[:position].blank? }
      if rows_without_position.size == @rows.size
        @errors << "Position column is required for crew imports. Please include a 'Position' column and make sure every row has a value in this column."
      elsif rows_without_position.any?
        @errors << "#{rows_without_position.size} row(s) are missing a position"
      end
    end
  end

  def normalize_row(row)
    name_data = parse_name(find_column(row, "name"))
    id_data = parse_id(find_column(row, "student", "id"))
    user_id_raw = find_column(row, "user_id") ||
                  find_column(row, "user id") ||
                  find_column(row, "userid")

    # Email handling: accept multiple column names for flexibility
    raw_email = find_column(row, "email")
    email = raw_email.to_s.strip.downcase.presence
    if email.blank? && id_data[:student_id].present?
      email = "#{id_data[:student_id]}@ed.ac.uk"
    end

    result = name_data.merge(id_data).merge(
      user_id: parse_user_id(user_id_raw),
      email: email
    )

    # Add position for crew imports
    if @import_mode == :crew
      result[:position] = find_column(row, "position").to_s.strip.presence
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
    # 0. Match by database primary key (highest priority)
    if row[:user_id].present?
      user = User.find_by(id: row[:user_id])
      return [ :exact_match_id, user ] if user
    end

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
