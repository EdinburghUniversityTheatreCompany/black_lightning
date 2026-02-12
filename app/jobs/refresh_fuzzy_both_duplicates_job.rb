##
# Background job to refresh fuzzy-both-names duplicate detection.
# Groups users by first letter of last name to reduce O(n²) to manageable size.
# Stores results in cached_duplicates table for fast page loads.
##
class RefreshFuzzyBothDuplicatesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting fuzzy-both-names duplicate refresh..."

    # Clear old results
    CachedDuplicate.delete_all

    # Group users by first letter of last name
    users_by_letter = User.all.to_a.group_by { |u| u.last_name&.first&.upcase || "Z" }

    # Process each letter group
    users_by_letter.each do |letter, users|
      Rails.logger.info "Processing #{users.size} users with last name starting with '#{letter}'"
      check_group(users)
    end

    Rails.logger.info "Completed: found #{CachedDuplicate.count} fuzzy-both-names duplicates"
  end

  private

  def check_group(users)
    # Bulk-load years_active for performance
    all_user_ids = users.map(&:id)
    years_active_cache = User.bulk_years_active_for(all_user_ids)

    # Track processed pairs to avoid duplicates
    processed_pairs = Set.new

    # Check all combinations within this group
    users.combination(2).each do |user1, user2|
      pair_id = [ user1.id, user2.id ].sort

      next if processed_pairs.include?(pair_id)
      next if user1.marked_not_duplicate?(user2)

      # Skip exact last name matches (those belong in buckets 2/3)
      next if user1.last_name && user2.last_name && user1.last_name.casecmp?(user2.last_name)

      # Check fuzzy matching on both names
      next unless User.fuzzy_last_name_match?(user1.last_name, user2.last_name)
      next unless User.fuzzy_first_name_match?(user1.first_name, user2.first_name)

      # Determine bucket type based on year overlap
      bucket_type = if user1.years_overlap?(user2, years_active_cache: years_active_cache)
        "overlapping"
      else
        "no_overlap"
      end

      # Store result
      CachedDuplicate.create!(
        user1_id: [ user1.id, user2.id ].min,
        user2_id: [ user1.id, user2.id ].max,
        bucket_type: bucket_type
      )

      processed_pairs << pair_id
    end
  end
end
