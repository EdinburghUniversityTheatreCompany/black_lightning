# frozen_string_literal: true

# What the user and membership imports share: finding the existing users a row matches and the
# years-active lookup their previews show for the candidates. Works on the @rows, @errors and
# @categorized of an ImportParsing class.
module UserMatching
  extend ActiveSupport::Concern

  ID_LOOKUPS = { user_id: :id, student_id: :student_id, associate_id: :associate_id }.freeze

  included do
    attr_reader :years_active_cache
  end

  def valid?
    @errors.empty? && @rows.any?
  end

  private

  # [user, match_type] for the first exact match, trying database id, student id, associate id,
  # then email (match_type is nil for email). Nil when nothing matches.
  def exact_match(row)
    ID_LOOKUPS.each do |key, column|
      user = row[key].presence && User.find_by(column => row[key])
      return [ user, key ] if user
    end

    user = row[:email].presence && User.find_by(email: row[:email])
    [ user, nil ] if user
  end

  # Last name exact, first name fuzzy, best match first.
  def fuzzy_matches(row, eligible_ids)
    return [] if row[:last_name].blank?

    User.where(last_name: row[:last_name]).where(id: eligible_ids)
        .select { |user| User.fuzzy_first_name_match?(row[:first_name], user.first_name) }
        .sort_by { |user| -StringSimilarity.match_confidence(row[:first_name], user.first_name) }
  end

  # One query for every candidate's years_active, to avoid N+1 in the preview.
  def years_active_cache_for(bucket)
    ids = @categorized[bucket].flat_map { |item| item[:existing_users].map(&:id) }
    ids.empty? ? {} : User.bulk_years_active_for(ids)
  end

  # Users on an event team since September, `years` academic years ago.
  def user_ids_active_since(years)
    from = Date.new(ApplicationController.helpers.date_to_academic_year(Date.current) - years, 9, 1)

    TeamMember.joins("INNER JOIN events ON events.id = team_members.teamwork_id")
              .where(teamwork_type: "Event")
              .where("events.start_date >= :from OR events.end_date >= :from", from: from)
              .distinct
              .pluck(:user_id)
  end
end
