# frozen_string_literal: true

# Parses pasted TSV or an uploaded xlsx and sorts each row into a BUCKETS entry by how it matches
# existing users.
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
    id_data = collect_ids_from_row(row)

    name_data.merge(id_data).merge(
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
    @eligible_user_ids = eligible_user_ids_for_matching

    build_categorized_result(multi_match_bucket: :propose_merge)
  end

  def determine_bucket(row)
    # Priority: database id, student id, associate id, email, then fuzzy name.
    if row[:user_id].present?
      user = User.find_by(id: row[:user_id])
      if user
        bucket = user.member? ? :already_active : :activate_by_id
        return [ bucket, user, :user_id ]
      end
    end

    if row[:student_id].present?
      user = User.find_by(student_id: row[:student_id])
      if user
        bucket = user.member? ? :already_active : :activate_by_id
        return [ bucket, user, :student_id ]
      end
    end

    if row[:associate_id].present?
      user = User.find_by(associate_id: row[:associate_id])
      if user
        bucket = user.member? ? :already_active : :activate_by_id
        return [ bucket, user, :associate_id ]
      end
    end

    if row[:email].present?
      user = User.find_by(email: row[:email])
      if user
        bucket = user.member? ? :already_active : :activate_by_email
        return [ bucket, user, nil ]
      end
    end

    # Last name exact, first name fuzzy, among users eligible for fuzzy matching.
    if row[:last_name].present?
      candidates = User.where(last_name: row[:last_name]).where(id: @eligible_user_ids)
      matches = candidates
        .select { |user| User.fuzzy_first_name_match?(row[:first_name], user.first_name) }
        .sort_by { |user| -StringSimilarity.match_confidence(row[:first_name], user.first_name) }
      return [ :propose_merge, matches, nil ] if matches.any?
    end

    [ :create_new, nil, nil ]
  end

  # One query for every candidate's years_active, to avoid N+1 in the preview.
  def load_years_active_cache
    fuzzy_user_ids = @categorized[:propose_merge].flat_map { |item| item[:existing_users].map(&:id) }
    return {} if fuzzy_user_ids.empty?

    User.bulk_years_active_for(fuzzy_user_ids)
  end

  # Fuzzy-match candidates: on an event team in the last 5 academic years, or on no team at all
  # (e.g. a new account).
  def eligible_user_ids_for_matching
    current_academic_year = ApplicationController.helpers.date_to_academic_year(Date.current)
    threshold_year = current_academic_year - 5
    threshold_date = Date.new(threshold_year, 9, 1)

    active_ids = TeamMember.unscoped
                           .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                           .where(teamwork_type: "Event")
                           .where("events.start_date >= ? OR events.end_date >= ?", threshold_date, threshold_date)
                           .distinct
                           .pluck(:user_id)

    users_with_memberships = TeamMember.unscoped.distinct.pluck(:user_id)
    no_activity_ids = User.where.not(id: users_with_memberships).pluck(:id)

    active_ids | no_activity_ids
  end
end
