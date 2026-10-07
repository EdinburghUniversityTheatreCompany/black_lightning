# frozen_string_literal: true

# Parses pasted TSV or an uploaded xlsx and sorts each row into a BUCKETS entry by how it matches
# existing users. Used by the bulk user import and the show crew import.
class UserImport
  include ImportParsing
  include UserMatching

  BUCKETS = %i[exact_match_id exact_match_email fuzzy_match create_new].freeze

  # What the previews call each id an exact_match_id row matched on.
  MATCH_TYPE_LABELS = { user_id: "User ID", student_id: "Student ID", associate_id: "Associate ID" }.freeze

  def initialize(data, input_type:, import_mode: :user)
    @errors = []
    @import_mode = import_mode
    @rows = parse_data(data, input_type)
    validate_rows
    @categorized = categorize_rows
    @years_active_cache = years_active_cache_for(:fuzzy_match)
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
    @active_user_ids = user_ids_active_since(3)

    build_categorized_result(multi_match_bucket: :fuzzy_match)
  end

  def determine_bucket(row)
    user, match_type = exact_match(row)
    return [ match_type ? :exact_match_id : :exact_match_email, user, match_type ] if user

    matches = fuzzy_matches(row, @active_user_ids)
    matches.any? ? [ :fuzzy_match, matches, nil ] : [ :create_new, nil, nil ]
  end
end
