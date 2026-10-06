##
# Refreshes cached_duplicates with pairs whose first and last names are both fuzzy matches.
# Users are grouped by the first letter of the last name to keep the O(n²) scan manageable.
##
class RefreshFuzzyBothDuplicatesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting fuzzy-both-names duplicate refresh..."

    CachedDuplicate.delete_all

    # Narrow select: every user is resident for the O(n²) scan, and a full row carries ~40
    # columns, so this keeps peak RSS proportional to the work.
    users_by_letter = User.where.not(last_name: [ nil, "" ])
                          .select(:id, :first_name, :last_name, :not_duplicate_user_ids)
                          .to_a.group_by { |u| u.last_name.first.upcase }

    users_by_letter.each do |letter, users|
      Rails.logger.info "Processing #{users.size} users with last name starting with '#{letter}'"
      check_group(users)
    end

    Rails.logger.info "Completed: found #{CachedDuplicate.count} fuzzy-both-names duplicates"
  end

  private

  def check_group(users)
    all_user_ids = users.map(&:id)
    years_active_cache = User.bulk_years_active_for(all_user_ids)

    processed_pairs = Set.new

    users.combination(2).each do |user1, user2|
      pair_id = [ user1.id, user2.id ].sort

      next if processed_pairs.include?(pair_id)
      next if user1.marked_not_duplicate?(user2)

      # Exact last names belong in buckets 2/3 of User.find_potential_duplicates.
      next if user1.last_name.casecmp?(user2.last_name)

      next unless StringSimilarity.fuzzy_name_match?(user1.last_name, user2.last_name)
      next unless StringSimilarity.fuzzy_name_match?(user1.first_name, user2.first_name)

      bucket_type = if user1.years_overlap?(user2, years_active_cache: years_active_cache)
        "overlapping"
      else
        "no_overlap"
      end

      CachedDuplicate.create!(
        user1_id: [ user1.id, user2.id ].min,
        user2_id: [ user1.id, user2.id ].max,
        bucket_type: bucket_type
      )

      processed_pairs << pair_id
    end
  end
end
