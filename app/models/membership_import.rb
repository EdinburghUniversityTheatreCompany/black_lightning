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

  attr_reader :years_active_cache

  def initialize(data, input_type:)
    @errors = []
    @rows = parse_data(data, input_type)
    @categorized = categorize_rows
    @years_active_cache = load_years_active_cache
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

    @eligible_user_ids = eligible_user_ids_for_matching

    @rows.each_with_index do |row, index|
      bucket, match, match_type = determine_bucket(row)
      if bucket == :propose_merge
        result[bucket] << { row: row, existing_users: match, index: index, match_type: match_type }
      else
        result[bucket] << { row: row, existing_user: match, index: index, match_type: match_type }
      end
    end

    result
  end

  def determine_bucket(row)
    # 0. Match by database primary key (highest priority)
    if row[:user_id].present?
      user = User.find_by(id: row[:user_id])
      if user
        bucket = user.has_role?(:member) ? :already_active : :activate_by_id
        return [ bucket, user, :user_id ]
      end
    end

    # 1. Match by student_id
    if row[:student_id].present?
      user = User.find_by(student_id: row[:student_id])
      if user
        bucket = user.has_role?(:member) ? :already_active : :activate_by_id
        return [ bucket, user, :student_id ]
      end
    end

    # 2. Match by associate_id
    if row[:associate_id].present?
      user = User.find_by(associate_id: row[:associate_id])
      if user
        bucket = user.has_role?(:member) ? :already_active : :activate_by_id
        return [ bucket, user, :associate_id ]
      end
    end

    # 3. Match by email
    if row[:email].present?
      user = User.find_by(email: row[:email])
      if user
        bucket = user.has_role?(:member) ? :already_active : :activate_by_email
        return [ bucket, user, nil ]
      end
    end

    # 4. Fuzzy name match (last name exact, first name fuzzy)
    # Only consider users active in last 5 years or with no activity on record
    if row[:last_name].present?
      candidates = User.where(last_name: row[:last_name]).where(id: @eligible_user_ids)
      matches = candidates
        .select { |user| User.fuzzy_first_name_match?(row[:first_name], user.first_name) }
        .sort_by { |user| -StringSimilarity.match_confidence(row[:first_name], user.first_name) }
      return [ :propose_merge, matches, nil ] if matches.any?
    end

    # 5. No match found - create new
    [ :create_new, nil, nil ]
  end

  # Bulk-load years_active for all users in the propose_merge bucket to avoid N+1 queries.
  def load_years_active_cache
    fuzzy_user_ids = @categorized[:propose_merge].flat_map { |item| item[:existing_users].map(&:id) }
    return {} if fuzzy_user_ids.empty?

    User.bulk_years_active_for(fuzzy_user_ids)
  end

  # Get IDs of users eligible for fuzzy matching:
  # - Users active in the last 5 years (have team memberships on recent events), OR
  # - Users with no team memberships at all (e.g., newly created accounts)
  def eligible_user_ids_for_matching
    current_academic_year = ApplicationController.helpers.date_to_academic_year(Date.current)
    threshold_year = current_academic_year - 5
    threshold_date = Date.new(threshold_year, 9, 1)

    # Users with recent activity
    active_ids = TeamMember.unscoped
                           .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                           .where(teamwork_type: "Event")
                           .where("events.start_date >= ? OR events.end_date >= ?", threshold_date, threshold_date)
                           .distinct
                           .pluck(:user_id)

    # Users with no team memberships at all
    users_with_memberships = TeamMember.unscoped.distinct.pluck(:user_id)
    no_activity_ids = User.where.not(id: users_with_memberships).pluck(:id)

    active_ids | no_activity_ids
  end
end
