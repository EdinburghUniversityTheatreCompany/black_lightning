# frozen_string_literal: true

# Parses pasted TSV or an uploaded xlsx and sorts each row into a BUCKETS entry by how it matches
# existing users.
class MembershipImport
  include ImportParsing
  include UserMatching

  BUCKETS = %i[already_active activate_by_id activate_by_email propose_merge create_new].freeze

  def initialize(data, input_type:)
    @errors = []
    @rows = parse_data(data, input_type)
    @categorized = categorize_rows
    @years_active_cache = years_active_cache_for(:propose_merge)
  end

  private

  def normalize_row(row)
    parse_name(row["Name"])
      .merge(collect_ids_from_row(row))
      .merge(email: row["Purchaser Email"].to_s.strip.downcase.presence)
  end

  def categorize_rows
    # Fuzzy-match candidates: on an event team in the last 5 academic years, or on no team at all
    # (e.g. a new account).
    @eligible_user_ids = user_ids_active_since(5) | User.where.not(id: TeamMember.distinct.pluck(:user_id)).pluck(:id)

    build_categorized_result(multi_match_bucket: :propose_merge)
  end

  def determine_bucket(row)
    user, match_type = exact_match(row)
    if user
      bucket = user.member? ? :already_active : (match_type ? :activate_by_id : :activate_by_email)
      return [ bucket, user, match_type ]
    end

    matches = fuzzy_matches(row, @eligible_user_ids)
    matches.any? ? [ :propose_merge, matches, nil ] : [ :create_new, nil, nil ]
  end
end
