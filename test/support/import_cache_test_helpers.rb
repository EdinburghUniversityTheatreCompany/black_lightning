# Shared helpers for the bulk-import controller tests (membership / user / crew).
#
# These tests seed the import cache with categorized rows, then POST :confirm.
# The cache payload is a hash of bucket-name => [entry, ...]. Each entry has the
# shape { "row" => {...}, "existing_user_id" => id_or_nil, "index" => n }
# (or "existing_user_ids" => [...] for the fuzzy/propose-merge buckets).
#
# Building those entries by hand is verbose and was duplicated across the
# membership and user import controller tests; these helpers centralise it.
module ImportCacheTestHelpers
  # Build a single categorized-row cache entry.
  #
  # Pass row fields as keyword args (they become the inner "row" hash with
  # string keys). Supply either existing_user_id: (single match) or
  # existing_user_ids: (multi-match buckets).
  def import_entry(index:, existing_user_id: nil, existing_user_ids: nil, **row_fields)
    entry = { "row" => row_fields.transform_keys(&:to_s), "index" => index }
    if existing_user_ids
      entry["existing_user_ids"] = existing_user_ids
    else
      entry["existing_user_id"] = existing_user_id
    end
    entry
  end

  # Write a categorized-import payload to the cache under cache_key.
  # Bucket lists are passed as keyword args; any omitted bucket defaults to [].
  def write_import_cache(cache_key, buckets)
    Rails.cache.write(cache_key, buckets.transform_keys(&:to_s), expires_in: 1.hour)
  end

  # Build a MembershipImport categorized payload. Supply only the non-empty
  # buckets; the rest default to []. Keeps the five-bucket skeleton in one place.
  def membership_import_buckets(already_active: [], activate_by_id: [], activate_by_email: [], propose_merge: [], create_new: [])
    {
      "already_active" => already_active,
      "activate_by_id" => activate_by_id,
      "activate_by_email" => activate_by_email,
      "propose_merge" => propose_merge,
      "create_new" => create_new
    }
  end

  # Build a UserImport categorized payload. Supply only the non-empty buckets;
  # the rest default to []. Keeps the four-bucket skeleton in one place.
  def user_import_buckets(exact_match_id: [], exact_match_email: [], fuzzy_match: [], create_new: [])
    {
      "exact_match_id" => exact_match_id,
      "exact_match_email" => exact_match_email,
      "fuzzy_match" => fuzzy_match,
      "create_new" => create_new
    }
  end

  # The standard two create_new entries ("Create Me" + "Skip Me") used by the
  # "handles multiple actions" tests in both import controllers.
  def create_me_and_skip_me_entries
    [
      import_entry(index: 1, original_name: "Create Me", first_name: "Create", last_name: "Me", student_id: "s2222222", email: "create@example.com"),
      import_entry(index: 2, original_name: "Skip Me", first_name: "Skip", last_name: "Me", student_id: "s3333333", email: "skip@example.com")
    ]
  end
end
