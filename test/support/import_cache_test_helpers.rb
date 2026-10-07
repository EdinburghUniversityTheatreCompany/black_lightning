# Helpers for the membership and user import controller tests, which seed the import
# cache and then POST :confirm. The cache payload is a hash of bucket-name => [entry, ...],
# each entry { "row" => {...}, "existing_user_id" => id_or_nil, "index" => n }
# (or "existing_user_ids" => [...] for the fuzzy/propose-merge buckets).
module ImportCacheTestHelpers
  # Row fields are keyword args; existing_user_ids: is for the multi-match buckets.
  def import_entry(index:, existing_user_id: nil, existing_user_ids: nil, **row_fields)
    entry = { "row" => row_fields.transform_keys(&:to_s), "index" => index }
    if existing_user_ids
      entry["existing_user_ids"] = existing_user_ids
    else
      entry["existing_user_id"] = existing_user_id
    end
    entry
  end

  def write_import_cache(cache_key, buckets)
    Rails.cache.write(cache_key, buckets.transform_keys(&:to_s), expires_in: 1.hour)
  end

  def create_me_and_skip_me_entries
    [
      import_entry(index: 1, original_name: "Create Me", first_name: "Create", last_name: "Me", student_id: "s2222222", email: "create@example.com"),
      import_entry(index: 2, original_name: "Skip Me", first_name: "Skip", last_name: "Me", student_id: "s3333333", email: "skip@example.com")
    ]
  end
end
