# frozen_string_literal: true

# Parses pasted TSV or an uploaded xlsx and sorts each row into a BUCKETS entry by how it matches
# existing users. Used by the bulk user import and the show crew import.
class UserImport
  include ImportParsing

  BUCKETS = %i[exact_match_id exact_match_email fuzzy_match create_new].freeze

  attr_reader :years_active_cache

  def initialize(data, input_type:, import_mode: :user)
    @errors = []
    @import_mode = import_mode
    @rows = parse_data(data, input_type)
    validate_rows
    @categorized = categorize_rows
    @years_active_cache = load_years_active_cache
  end

  def valid?
    @errors.empty? && @rows.any?
  end

  private

  def validate_rows
    return if @rows.empty?

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
    id_data = collect_ids_from_row(row)

    raw_email = find_column(row, "email")
    email = raw_email.to_s.strip.downcase.presence
    if email.blank? && id_data[:student_id].present?
      email = "#{id_data[:student_id]}@ed.ac.uk"
    end

    result = name_data.merge(id_data).merge(
      email: email
    )

    if @import_mode == :crew
      result[:position] = find_column(row, "position").to_s.strip.presence
    end

    result
  end

  def categorize_rows
    @active_user_ids = active_user_ids_for_matching

    build_categorized_result(multi_match_bucket: :fuzzy_match)
  end

  def determine_bucket(row)
    # Priority: database id, student id, associate id, email, then fuzzy name.
    if row[:user_id].present?
      user = User.find_by(id: row[:user_id])
      return [ :exact_match_id, user, :user_id ] if user
    end

    if row[:student_id].present?
      user = User.find_by(student_id: row[:student_id])
      return [ :exact_match_id, user, :student_id ] if user
    end

    if row[:associate_id].present?
      user = User.find_by(associate_id: row[:associate_id])
      return [ :exact_match_id, user, :associate_id ] if user
    end

    if row[:email].present?
      user = User.find_by(email: row[:email])
      return [ :exact_match_email, user, nil ] if user
    end

    # Last name exact, first name fuzzy, among active users only.
    if row[:last_name].present?
      candidates = User.where(last_name: row[:last_name]).where(id: @active_user_ids)
      matches = candidates
        .select { |user| User.fuzzy_first_name_match?(row[:first_name], user.first_name) }
        .sort_by { |user| -StringSimilarity.match_confidence(row[:first_name], user.first_name) }
      return [ :fuzzy_match, matches, nil ] if matches.any?
    end

    [ :create_new, nil, nil ]
  end

  # One query for every candidate's years_active, to avoid N+1 in the preview.
  def load_years_active_cache
    fuzzy_user_ids = @categorized[:fuzzy_match].flat_map { |item| item[:existing_users].map(&:id) }
    return {} if fuzzy_user_ids.empty?

    User.bulk_years_active_for(fuzzy_user_ids)
  end

  # Fuzzy matching only considers users on an event team since September, 3 academic years ago.
  def active_user_ids_for_matching
    current_academic_year = ApplicationController.helpers.date_to_academic_year(Date.current)
    threshold_year = current_academic_year - 3
    threshold_date = Date.new(threshold_year, 9, 1)

    TeamMember.unscoped
              .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
              .where(teamwork_type: "Event")
              .where("events.start_date >= ? OR events.end_date >= ?", threshold_date, threshold_date)
              .distinct
              .pluck(:user_id)
  end
end
