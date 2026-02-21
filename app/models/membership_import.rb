# frozen_string_literal: true

##
# Service-like model for parsing membership import data and categorizing rows.
# Not backed by a database table.
#
# Accepts either pasted TSV data or an uploaded xlsx file.
# Categorizes each row into one of five buckets based on matching rules.
##
class MembershipImport
  include ImportParsing

  BUCKETS = %i[already_active activate_by_id activate_by_email propose_merge create_new].freeze

  def initialize(data, input_type:)
    @errors = []
    @rows = parse_data(data, input_type)
    @categorized = categorize_rows
  end

  def valid?
    @errors.empty? && @rows.any?
  end

  private

  def normalize_row(row)
    name_data = parse_name(row["Name"])
    id_data = parse_id(row["Student ID"])
    user_id_raw = find_column(row, "user_id") ||
                  find_column(row, "user id") ||
                  find_column(row, "userid")

    name_data.merge(id_data).merge(
      user_id: parse_user_id(user_id_raw),
      email: row["Purchaser Email"].to_s.strip.downcase.presence,
      member_type: row["Member Type"].to_s.strip.presence,
      date_purchased: parse_date(row["Date Purchased"])
    )
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
    # 0. Match by database primary key (highest priority)
    if row[:user_id].present?
      user = User.find_by(id: row[:user_id])
      if user
        return user.has_role?(:member) ? [ :already_active, user ] : [ :activate_by_id, user ]
      end
    end

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
